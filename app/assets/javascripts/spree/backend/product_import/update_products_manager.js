/**
 * Update Products Manager
 * Handles all UI behaviour for the "Update Products" section:
 *   - Per-row collapse / expand
 *   - Toggle-all rows
 *   - Select / deselect all checkboxes
 *   - Bulk-set modal (available_on, shipping_category, vendor, taxons)
 *   - Boot: Select2, Flatpickr, modal-prefix registration, form-submit hook
 */

// Ensure Spree namespace exists
window.Spree = window.Spree || {};
window.Spree.ProductImport = window.Spree.ProductImport || {};

Spree.ProductImport.UpdateProductsManager = (function () {
  'use strict';

  // ========== DOM Helpers ==========

  function allUpdateCards() {
    return Array.from(document.querySelectorAll('.update-product-card'));
  }

  function getCardBody(pId) {
    return document.getElementById('update-row-body-' + pId);
  }

  function getChevron(pId) {
    return document.querySelector('[data-role="update-row-chevron-' + pId + '"]');
  }

  // ========== UI Updates ==========

  function setAllRows(expanded) {
    allUpdateCards().forEach(function (card) {
      var pId  = card.getAttribute('data-product-id');
      var body = getCardBody(pId);
      var chev = getChevron(pId);
      if (!body) return;
      body.style.display = expanded ? '' : 'none';
      if (chev) chev.style.transform = expanded ? 'rotate(90deg)' : 'rotate(0deg)';
    });
  }

  // ========== Row Collapse / Expand ==========

  function attachRowToggleListeners() {
    var headers = document.querySelectorAll('[data-action="toggle-update-row"]');
    headers.forEach(function (header) {
      header.addEventListener('click', function () {
        var pId     = header.closest('[data-product-id]').getAttribute('data-product-id');
        var body    = getCardBody(pId);
        var chevron = getChevron(pId);
        if (!body) return;
        var expanded = body.style.display !== 'none';
        body.style.display = expanded ? 'none' : '';
        if (chevron) chevron.style.transform = expanded ? 'rotate(0deg)' : 'rotate(90deg)';
      });
    });
  }

  // ========== Toggle All ==========

  function attachToggleAllListener() {
    var toggleAllBtn = document.getElementById('update-toggle-all-btn');
    if (!toggleAllBtn) return;

    toggleAllBtn.addEventListener('click', function () {
      var isExpanded    = toggleAllBtn.getAttribute('data-state') === 'expanded';
      var expandLabel   = toggleAllBtn.getAttribute('data-label-expand')   || 'Expand All';
      var collapseLabel = toggleAllBtn.getAttribute('data-label-collapse') || 'Collapse All';

      setAllRows(!isExpanded);
      toggleAllBtn.setAttribute('data-state', isExpanded ? 'collapsed' : 'expanded');

      var label = document.getElementById('update-toggle-all-label');
      if (label) label.textContent = isExpanded ? expandLabel : collapseLabel;
    });
  }

  // ========== Select / Deselect All ==========

  function updateSaveButtonState() {
    var checkedCount = document.querySelectorAll('.update-row-checkbox:checked').length;
    var saveButtons = document.querySelectorAll('.update-save-btn');
    saveButtons.forEach(function (btn) {
      btn.disabled = (checkedCount === 0);
    });
  }

  function attachSelectAllListeners() {
    var selectAllCb = document.getElementById('update-select-all-checkbox');
    var rowCheckboxes = document.querySelectorAll('.update-row-checkbox');

    if (selectAllCb) {
      selectAllCb.addEventListener('change', function () {
        document.querySelectorAll('.update-row-checkbox').forEach(function (cb) {
          cb.checked = selectAllCb.checked;
        });
        updateSaveButtonState();
      });
    }

    rowCheckboxes.forEach(function (cb) {
      cb.addEventListener('change', function () {
        var all          = document.querySelectorAll('.update-row-checkbox');
        var checkedCount = Array.from(all).filter(function (c) { return c.checked; }).length;
        if (selectAllCb) selectAllCb.checked = (checkedCount === all.length);
        updateSaveButtonState();
      });
    });

    // Initialize button state on page load
    updateSaveButtonState();
  }

  // ========== Bulk-Set Modal ==========

  var bulkModal        = null;
  var bulkTitleEl      = null;
  var currentBulkField = null;

  var bulkLabels = {
    available_on:      'Set Available On',
    shipping_category: 'Set Shipping Category',
    vendor:            'Set Vendor',
    taxons:            'Set Taxons'
  };

  function initBulkModalWidgets(field) {
    if (field === 'available_on') {
      var input = document.getElementById('update-bulk-available-on-value');
      if (input && !input._flatpickr && typeof flatpickr !== 'undefined') {
        var fp = flatpickr(input, {
          dateFormat:    'Y-m-d H:i:S',
          enableTime:    true,
          allowInput:    true,
          disableMobile: true,
          onOpen: function (selectedDates, dateStr, instance) {
            var cal  = instance.calendarContainer;
            var rect = input.getBoundingClientRect();
            cal.style.position = 'fixed';
            cal.style.top      = (rect.bottom + 2) + 'px';
            cal.style.left     = rect.left + 'px';
            cal.style.zIndex   = '99999';
          }
        });
        var clearBtn = document.getElementById('update-bulk-datepicker-clear');
        if (clearBtn) {
          clearBtn.addEventListener('click', function () { fp.clear(); });
        }
      }
    } else if (field === 'shipping_category') {
      var sel = document.getElementById('update-bulk-shipping-category-value');
      if (sel && typeof jQuery !== 'undefined' && jQuery.fn.select2 && !jQuery(sel).data('select2')) {
        jQuery(sel).select2({ dropdownParent: jQuery('#update-bulk-modal'), width: '100%', allowClear: true, placeholder: '— None —' });
      }
    } else if (field === 'vendor') {
      var sel = document.getElementById('update-bulk-vendor-value'); // jshint ignore:line
      if (sel && typeof jQuery !== 'undefined' && jQuery.fn.select2 && !jQuery(sel).data('select2')) {
        jQuery(sel).select2({ dropdownParent: jQuery('#update-bulk-modal'), width: '100%', allowClear: true, placeholder: '— None —' });
      }
    } else if (field === 'taxons') {
      var sel = document.getElementById('update-bulk-taxons-value'); // jshint ignore:line
      if (sel && typeof jQuery !== 'undefined' && jQuery.fn.select2 && !jQuery(sel).data('select2')) {
        jQuery(sel).select2({ dropdownParent: jQuery('#update-bulk-modal'), width: '100%', placeholder: 'Select taxons...' });
      }
    }
  }

  function openBulkModal(field) {
    currentBulkField = field;
    if (bulkTitleEl) bulkTitleEl.textContent = bulkLabels[field] || 'Set Value';

    document.querySelectorAll('.update-bulk-field-section').forEach(function (s) {
      s.style.display = 'none';
    });
    var sec = document.getElementById('update-bulk-field-' + field);
    if (sec) sec.style.display = 'block';

    // Update scope banner
    var scopeLabel   = document.getElementById('update-bulk-scope-label');
    if (scopeLabel) {
      var checkedCount = document.querySelectorAll('.update-row-checkbox:checked').length;
      scopeLabel.textContent = checkedCount > 0
        ? 'Applying to ' + checkedCount + ' selected product' + (checkedCount !== 1 ? 's' : '') + '.'
        : 'No products selected – nothing will be changed.';
    }

    // Lazy-init widgets
    initBulkModalWidgets(field);
    if (bulkModal) bulkModal.style.display = 'flex';
  }

  function closeBulkModal() {
    if (bulkModal) bulkModal.style.display = 'none';
    currentBulkField = null;
  }

  function applyBulkChanges() {
    var selected = allUpdateCards().filter(function (c) {
      var cb = c.querySelector('.update-row-checkbox');
      return cb && cb.checked;
    });

    selected.forEach(function (card) {
      var pId  = card.getAttribute('data-product-id');
      var body = getCardBody(pId);
      if (!body) return;

      if (currentBulkField === 'available_on') {
        var v       = document.getElementById('update-bulk-available-on-value');
        var wrapper = body.querySelector('.update-available-on-datepicker');
        if (v && wrapper) {
          if (wrapper._flatpickr) {
            wrapper._flatpickr.setDate(v.value, true);
          } else {
            var t = wrapper.querySelector('[data-role="update-available-on-input"]');
            if (t) t.value = v.value;
          }
        }
      } else if (currentBulkField === 'shipping_category') {
        var s  = document.getElementById('update-bulk-shipping-category-value');
        var t  = body.querySelector('[data-role="update-shipping-category-input"]'); // jshint ignore:line
        if (s && t) {
          if (typeof jQuery !== 'undefined' && jQuery.fn.select2 && jQuery(t).data('select2')) {
            jQuery(t).val(s.value).trigger('change');
          } else {
            t.value = s.value;
          }
        }
      } else if (currentBulkField === 'vendor') {
        var vs = document.getElementById('update-bulk-vendor-value');
        var vt = body.querySelector('[data-role="row-vendor-select"]');
        if (vs && vt) {
          if (typeof jQuery !== 'undefined' && jQuery.fn.select2 && jQuery(vt).data('select2')) {
            jQuery(vt).val(vs.value).trigger('change');
          } else {
            vt.value = vs.value;
          }
        }
      } else if (currentBulkField === 'taxons') {
        var ts = document.getElementById('update-bulk-taxons-value');
        var tt = body.querySelector('[data-role="update-taxons-input"]');
        if (ts && tt && typeof jQuery !== 'undefined' && jQuery.fn.select2) {
          var vals = Array.from(ts.selectedOptions).map(function (o) { return o.value; });
          jQuery(tt).val(vals).trigger('change');
        }
      }
    });

    closeBulkModal();
  }

  function attachBulkModalListeners() {
    bulkModal   = document.getElementById('update-bulk-modal');
    bulkTitleEl = document.getElementById('update-bulk-modal-title');

    var bulkCloseBtn  = document.getElementById('update-bulk-modal-close');
    var bulkCancelBtn = document.getElementById('update-bulk-modal-cancel');
    var bulkApplyBtn  = document.getElementById('update-bulk-modal-apply');

    if (bulkCloseBtn)  bulkCloseBtn.addEventListener('click',  closeBulkModal);
    if (bulkCancelBtn) bulkCancelBtn.addEventListener('click', closeBulkModal);
    if (bulkApplyBtn)  bulkApplyBtn.addEventListener('click',  applyBulkChanges);

    document.querySelectorAll('[data-action="update-bulk-set"]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        openBulkModal(btn.getAttribute('data-field'));
      });
    });
  }

  // ========== Confirmation Modal ==========

  var confirmModal = null;

  function openConfirmModal() {
    var checkedCount = document.querySelectorAll('.update-row-checkbox:checked').length;
    
    if (checkedCount === 0) {
      alert('Please select at least one product to update.');
      return;
    }

    var countEl = document.getElementById('update-confirm-count');
    if (countEl) {
      countEl.textContent = checkedCount;
    }

    if (confirmModal) {
      confirmModal.style.display = 'flex';
    }
  }

  function closeConfirmModal() {
    if (confirmModal) {
      confirmModal.style.display = 'none';
    }
  }

  function confirmAndSubmit() {
    closeConfirmModal();
    var updateForm = document.getElementById('product-update-form');
    if (updateForm) {
      // Trigger the form's submit event which is already hooked by initSubModules
      updateForm.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
    }
  }

  function attachConfirmModalListeners() {
    confirmModal = document.getElementById('update-confirm-modal');
    if (!confirmModal) return;

    var confirmCancelBtn = document.getElementById('update-confirm-cancel');
    var confirmSubmitBtn = document.getElementById('update-confirm-submit');

    if (confirmCancelBtn) {
      confirmCancelBtn.addEventListener('click', closeConfirmModal);
    }

    if (confirmSubmitBtn) {
      confirmSubmitBtn.addEventListener('click', confirmAndSubmit);
    }

    // Close on backdrop click
    confirmModal.addEventListener('click', function (e) {
      if (e.target === confirmModal) {
        closeConfirmModal();
      }
    });

    // Attach to all save buttons
    var saveButtons = document.querySelectorAll('.update-save-btn');
    saveButtons.forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        openConfirmModal();
      });
    });
  }

  // ========== Widget Initialization (Boot) ==========

  function boot() {
    var updateForm = document.getElementById('product-update-form');
      if (updateForm && typeof jQuery !== 'undefined' && jQuery.fn.select2) {
        jQuery(updateForm).find('select.select2').each(function () {
          jQuery(this).select2({
            theme:          'bootstrap4',
            closeOnSelect:  false,
            dropdownParent: jQuery(document.body)
          });
        });
      }

      // Initialize Select2 for vendor filter dropdown (Tab 1)
      var vFilter = document.getElementById('update-vendor-select');
      if (vFilter && typeof jQuery !== 'undefined' && jQuery.fn.select2) {
        jQuery(vFilter).select2({ theme: 'bootstrap4' });
      }

      // Handle clear button for search form (Tab 2)
      // var clearBtn = document.getElementById('update-search-clear');
      // if (clearBtn) {
      //   clearBtn.addEventListener('click', function() {
      //     // Clear text inputs
      //     var nameInput = document.getElementById('update-search-name');
      //     var skuInput = document.getElementById('update-search-sku');
      //     if (nameInput) nameInput.value = '';
      //     if (skuInput) skuInput.value = '';
          
      //     // Optionally reset per page to default
      //     var perPageSelect = document.getElementById('search-filter-per-page');
      //     if (perPageSelect) perPageSelect.value = '25';
      //   });
      // }

      if (typeof flatpickr !== 'undefined') {
        document.querySelectorAll('.update-available-on-datepicker[data-wrap]').forEach(function (wrapper) {
          if (!wrapper._flatpickr) {
            flatpickr(wrapper, {
              wrap:        true,
              altInput:    true,
              altFormat:   'M j, Y H:i',
              dateFormat:  'Y-m-d H:i:S',
              enableTime:  true,
              allowInput:  true
            });
          }
        });
      }
  }

  // ========== Sub-Module DOM Adapter ==========

  /**
   * Returns a DOM-helper-compatible object scoped to #update-products-section.
   * This lets DescriptionSeoManager, VariantManager, and ImageManager work
   * against update-product rows even though #product-import-table is absent.
   */
  function buildUpdateDomAdapter() {
    var root = document.getElementById('update-products-section');
    return {
      setTable:             function(el) { root = el; },
      getTable:             function() { return root; },
      rowParts:             function() { return { summary: null, details: null }; },
      getSelectedCheckboxes: function() { return []; },
      getCheckedCount:      function() { return 0; },
      getTemplate:          function() { return null; },
      getModal:             function(id) { return document.getElementById(id); },
      querySelector:        function(selector) { return root ? root.querySelector(selector) : null; },
      querySelectorAll:     function(selector) { return root ? root.querySelectorAll(selector) : []; }
    };
  }

  // ========== Sub-Module Initialization ==========

  function initSubModules() {
    var domAdapter = buildUpdateDomAdapter();
    var DescSeo   = Spree.ProductImport.DescriptionSeoManager;
    var Variants  = Spree.ProductImport.VariantManager;
    var Images    = Spree.ProductImport.ImageManager;
    var Stock     = Spree.ProductImport.StockManager;
    var Price     = Spree.ProductImport.PriceManager;

    if (DescSeo && typeof DescSeo.init === 'function') {
      DescSeo.init({ DOM: domAdapter, UI: null });
      // initializeExistingRows looks for .product-import-row-details which doesn't exist
      // in update-mode cards, so manually render summaries for every loaded product row.
      if (typeof DescSeo.updateSummary === 'function') {
        allUpdateCards().forEach(function (card) {
          var rowIdx = 'u_' + card.getAttribute('data-product-id');
          DescSeo.updateSummary(rowIdx);
        });
      }
    }
    if (Variants && typeof Variants.init === 'function') {
      Variants.init(domAdapter);
      if (window.spreeProductImportOptionTypes) {
        Variants.setOptionTypesData(window.spreeProductImportOptionTypes);
      }
    }
    if (Images && typeof Images.init === 'function') {
      Images.init(domAdapter);
    }
    if (Stock && typeof Stock.init === 'function') {
      var stockLocations = window.spreeProductImportStockLocations || [];
      Stock.init(stockLocations);
    }
    if (Price && typeof Price.init === 'function') {
      var defaultCurrency = window.spreeProductImportCurrency || 'USD';
      Price.init(defaultCurrency);
    }

    // Register per-row form bases so new variant/image inputs use the correct
    // param namespace (product_updates[id][...]) instead of the create default.
    var cards = allUpdateCards();
    
    cards.forEach(function (card) {

      var pId    = card.getAttribute('data-product-id');
      var rowIdx = 'u_' + pId;
      var variantBase = 'product_updates[' + pId + '][new_variants]';
      var imageBase = 'product_updates[' + pId + '][new_images]';
      
      if (Variants && typeof Variants.registerRowFormBase === 'function') {
        Variants.registerRowFormBase(rowIdx, variantBase);
      }
      if (Images && typeof Images.registerRowFormBase === 'function') {
        Images.registerRowFormBase(rowIdx, imageBase);
      }
    });

    // Render summaries and pre-populate form fields for server-seeded variant data
    if (Variants && typeof Variants.initializeExistingRows === 'function') {
      Variants.initializeExistingRows();
    }
    
    // Initialize stock summaries for existing products
    if (Stock && typeof Stock.initializeExistingRows === 'function') {
      Stock.initializeExistingRows();
    }
    
    // Initialize price summaries for existing products
    if (Price && typeof Price.initializeExistingRows === 'function') {
      Price.initializeExistingRows();
    }
    
    // Hook form submit to inject image file inputs (AFTER ImageManager is initialized)
    var updateForm = document.getElementById('product-update-form');
    if (updateForm && Images && typeof Images.prepareFormSubmission === 'function') {
      updateForm.addEventListener('submit', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        // Build FormData from the form
        var formData = new FormData(updateForm);
        
        // Get images data from ImageManager
        var imagesByRow = Images.getImagesByRow ? Images.getImagesByRow() : {};
        var rowFormBases = Images.getRowFormBases ? Images.getRowFormBases() : {};
        
        // Add images to FormData
        Object.keys(imagesByRow).forEach(function(rowIndex) {
          var images = imagesByRow[rowIndex];
          if (!images || images.length === 0) return;
          
          var formBase = rowFormBases[rowIndex];
          if (!formBase) return;
          
          images.forEach(function(imgData, idx) {
            var attachmentKey = formBase + '[' + idx + '][attachment]';
            var altKey = formBase + '[' + idx + '][alt]';
            
            formData.append(attachmentKey, imgData.file, imgData.file.name);
            formData.append(altKey, imgData.alt || '');
          });
        });
        
        // Submit via fetch
        fetch(updateForm.action, {
          method: 'POST',
          body: formData,
          headers: {
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
          },
          credentials: 'same-origin'
        })
        .then(function(response) {
          if (response.redirected) {
            window.location.href = response.url;
          } else {
            return response.text().then(function(html) {
              document.open();
              document.write(html);
              document.close();
            });
          }
        })
        .catch(function(error) {
          console.error('Submission error:', error);
          alert('Error submitting form: ' + error.message);
        });
      });
    }
  }

  // ========== Sub-Modal Event Listeners ==========

  function attachSubModalListeners() {
    var DescSeo  = Spree.ProductImport.DescriptionSeoManager;
    var Variants = Spree.ProductImport.VariantManager;
    var Images   = Spree.ProductImport.ImageManager;
    var Stock    = Spree.ProductImport.StockManager;
    var Price    = Spree.ProductImport.PriceManager;
    var section  = document.getElementById('update-products-section');

    // ── Document-level delegation for buttons inside the update section ──
    document.addEventListener('click', function (event) {
      if (!document.getElementById('update-products-section')) return;

      // Open Description & SEO modal
      var descBtn = event.target.closest('[data-action="open-description-seo-modal"]');
      if (descBtn && section && section.contains(descBtn)) {
        event.preventDefault();
        event.stopPropagation();
        if (DescSeo) DescSeo.openModal(descBtn.getAttribute('data-row-index'));
        return;
      }

      // Open Variant modal
      var varBtn = event.target.closest('[data-action="open-variant-modal"]');
      if (varBtn && section && section.contains(varBtn)) {
        event.preventDefault();
        event.stopPropagation();
        if (Variants) Variants.openVariantModal(varBtn.getAttribute('data-row-index'));
        return;
      }

      // Open Images modal
      var imgBtn = event.target.closest('[data-action="open-images-modal"]');
      if (imgBtn && section && section.contains(imgBtn)) {
        event.preventDefault();
        event.stopPropagation();
        var rowIndex = imgBtn.getAttribute('data-row-index');
        if (Images) Images.openModal(rowIndex);
        return;
      }

      // Open Stock modal
      var stockBtn = event.target.closest('[data-action="open-stock-modal"]');
      if (stockBtn && section && section.contains(stockBtn)) {
        event.preventDefault();
        event.stopPropagation();
        if (Stock) Stock.openStockModal(stockBtn.getAttribute('data-row-index'));
        return;
      }

      // Open Price modal
      var priceBtn = event.target.closest('[data-action="open-price-modal"]');
      if (priceBtn && section && section.contains(priceBtn)) {
        event.preventDefault();
        event.stopPropagation();
        if (Price) Price.openPriceModal(priceBtn.getAttribute('data-row-index'));
        return;
      }

      // Toggle Description & SEO section
      var dToggle = event.target.closest('[data-action="toggle-description-seo-section"]');
      if (dToggle && section && section.contains(dToggle)) {
        var dRowIdx  = dToggle.getAttribute('data-row-index');
        var dContent = section.querySelector('[data-role="description-seo-content"][data-row-index="' + dRowIdx + '"]');
        var dChevron = dToggle.querySelector('[data-role="description-seo-chevron"]');
        if (dContent) {
          var dVisible = dContent.style.display !== 'none';
          dContent.style.display = dVisible ? 'none' : 'block';
          if (dChevron) dChevron.style.transform = dVisible ? 'rotate(0deg)' : 'rotate(90deg)';
        }
        return;
      }

      // Toggle Variants section
      var vToggle = event.target.closest('[data-action="toggle-variants-section"]');
      if (vToggle && section && section.contains(vToggle)) {
        var vRowIdx  = vToggle.getAttribute('data-row-index');
        var vContent = section.querySelector('[data-role="variants-content"][data-row-index="' + vRowIdx + '"]');
        var vChevron = vToggle.querySelector('[data-role="variants-chevron"]');
        if (vContent) {
          var vVisible = vContent.style.display !== 'none';
          vContent.style.display = vVisible ? 'none' : 'block';
          if (vChevron) vChevron.style.transform = vVisible ? 'rotate(0deg)' : 'rotate(90deg)';
        }
        return;
      }

      // Toggle Images section
      var iToggle = event.target.closest('[data-action="toggle-images-section"]');
      if (iToggle && section && section.contains(iToggle)) {
        var iRowIdx  = iToggle.getAttribute('data-row-index');
        var iContent = section.querySelector('[data-role="images-content"][data-row-index="' + iRowIdx + '"]');
        var iChevron = iToggle.querySelector('[data-role="images-chevron"]');
        if (iContent) {
          var iVisible = iContent.style.display !== 'none';
          iContent.style.display = iVisible ? 'none' : 'block';
          if (iChevron) iChevron.style.transform = iVisible ? 'rotate(0deg)' : 'rotate(90deg)';
        }
        return;
      }

      // Toggle Stock section
      var sToggle = event.target.closest('[data-action="toggle-stock-section"]');
      if (sToggle && section && section.contains(sToggle)) {
        var sRowIdx  = sToggle.getAttribute('data-row-index');
        var sContent = section.querySelector('[data-role="stock-content"][data-row-index="' + sRowIdx + '"]');
        var sChevron = sToggle.querySelector('[data-role="stock-chevron"]');
        if (sContent) {
          var sVisible = sContent.style.display !== 'none';
          sContent.style.display = sVisible ? 'none' : 'block';
          if (sChevron) sChevron.style.transform = sVisible ? 'rotate(0deg)' : 'rotate(90deg)';
        }
        return;
      }

      // Toggle Price section
      var pToggle = event.target.closest('[data-action="toggle-price-section"]');
      if (pToggle && section && section.contains(pToggle)) {
        var pRowIdx  = pToggle.getAttribute('data-row-index');
        var pContent = section.querySelector('[data-role="price-content"][data-row-index="' + pRowIdx + '"]');
        var pChevron = pToggle.querySelector('[data-role="price-chevron"]');
        if (pContent) {
          var pVisible = pContent.style.display !== 'none';
          pContent.style.display = pVisible ? 'none' : 'block';
          if (pChevron) pChevron.style.transform = pVisible ? 'rotate(0deg)' : 'rotate(90deg)';
        }
        return;
      }
    });

    // ── Description & SEO modal ──────────────────────────────────────────
    var descSeoModal = document.getElementById('description-seo-modal');
    if (descSeoModal && DescSeo) {
      descSeoModal.addEventListener('click', function (event) {
        if (event.target === descSeoModal ||
            event.target.closest('[data-action="close-description-seo-modal"]')) {
          event.preventDefault();
          DescSeo.closeModal();
          return;
        }
        if (event.target.closest('[data-action="save-description-seo"]')) {
          event.preventDefault();
          DescSeo.saveData();
        }
      });
    }

    // ── Variant modal ────────────────────────────────────────────────────
    var variantModal = document.getElementById('variant-modal');
    if (variantModal && Variants) {
      variantModal.addEventListener('click', function (event) {
        if (event.target === variantModal ||
            event.target.closest('[data-action="close-variant-modal"]')) {
          event.preventDefault();
          Variants.closeVariantModal();
          return;
        }
        if (event.target.closest('[data-action="add-modal-variant"]')) {
          event.preventDefault();
          Variants.addModalVariant();
          return;
        }
        var removeVarBtn = event.target.closest('[data-action="remove-modal-variant"]');
        if (removeVarBtn) {
          event.preventDefault();
          var vId = parseInt(removeVarBtn.getAttribute('data-variant-id'), 10);
          if (vId) Variants.removeModalVariant(vId);
          return;
        }
        if (event.target.closest('[data-action="save-variants"]')) {
          event.preventDefault();
          Variants.saveVariantsToRow();
          return;
        }
        var toggleBtn = event.target.closest('[data-action="toggle-variant-card"]');
        if (toggleBtn) {
          event.preventDefault();
          var vId = parseInt(toggleBtn.getAttribute('data-variant-id'), 10);
          if (vId) Variants.toggleVariantCard(vId);
        }
      });

      variantModal.addEventListener('change', function (event) {
        if (event.target.classList.contains('modal-option-type-checkbox')) {
          Variants.handleModalOptionTypeChange(event.target);
        } else if (event.target.classList.contains('modal-variant-field')) {
          Variants.handleModalVariantFieldChange(event.target);
        }
      });

      variantModal.addEventListener('input', function (event) {
        if (event.target.classList.contains('modal-variant-field')) {
          Variants.handleModalVariantFieldChange(event.target);
        }
      });

      var searchInput = document.getElementById('option-types-search');
      if (searchInput) {
        searchInput.addEventListener('input', function () { Variants.filterOptionTypes(); });
      }
      var clearSearchBtn = document.getElementById('clear-option-types-search');
      if (clearSearchBtn) {
        clearSearchBtn.addEventListener('click', function (e) { e.preventDefault(); Variants.clearOptionTypesSearch(); });
      }
    }

    // ── Images modal ─────────────────────────────────────────────────────
    var imagesModal = document.getElementById('images-modal');
    if (imagesModal && Images) {
      imagesModal.addEventListener('click', function (event) {
        if (event.target === imagesModal ||
            event.target.closest('[data-action="close-images-modal"]')) {
          event.preventDefault();
          Images.closeModal();
          return;
        }
        if (event.target.closest('[data-action="add-modal-image"]')) {
          event.preventDefault();
          Images.addImageToQueue();
          return;
        }
        var removeImgBtn = event.target.closest('[data-action="remove-modal-image"]');
        if (removeImgBtn) {
          event.preventDefault();
          var imgId = parseInt(removeImgBtn.getAttribute('data-image-id'), 10);
          if (imgId) Images.removeImageFromQueue(imgId);
          return;
        }
        if (event.target.closest('[data-action="save-images"]')) {
          event.preventDefault();
          Images.saveImagesToRow();
        }
      });
    }

    // ── Stock modal ──────────────────────────────────────────────────────
    var stockModal = document.getElementById('stock-modal');
    if (stockModal && Stock) {
      stockModal.addEventListener('click', function (event) {
        if (event.target === stockModal ||
            event.target.closest('[data-action="close-stock-modal"]')) {
          event.preventDefault();
          Stock.closeStockModal();
          return;
        }
        if (event.target.closest('[data-action="save-stock"]')) {
          event.preventDefault();
          Stock.saveStockToRow();
        }
      });
    }

    // ── Price modal ──────────────────────────────────────────────────────
    var priceModal = document.getElementById('price-modal');
    if (priceModal && Price) {
      priceModal.addEventListener('click', function (event) {
        if (event.target === priceModal ||
            event.target.closest('[data-action="close-price-modal"]')) {
          event.preventDefault();
          Price.closePriceModal();
          return;
        }
        if (event.target.closest('[data-action="save-price"]')) {
          event.preventDefault();
          Price.savePriceToRow();
        }
      });
    }
  }

  // ========== Event Listeners ==========

  function attachEventListeners() {
    attachRowToggleListeners();
    attachToggleAllListener();
    attachSelectAllListeners();
    attachBulkModalListeners();
    attachConfirmModalListeners();
    attachSubModalListeners();
  }

  // ========== Public API ==========

  function init() {
    var section = document.getElementById('update-products-section');
    if (!section) return;
    
    boot();
    initSubModules();
    attachEventListeners();
  }

  return {
    init: init
  };
})();

// Auto-initialize on page load
(function () {
  function initializeUpdateProducts() {
    Spree.ProductImport.UpdateProductsManager.init();
  }

  document.addEventListener('DOMContentLoaded', initializeUpdateProducts);
  document.addEventListener('turbolinks:load', initializeUpdateProducts);
})()
