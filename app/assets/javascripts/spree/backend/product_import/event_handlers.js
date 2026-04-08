/**
 * Event Handlers
 * Central event handling and delegation for all table interactions
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.EventHandlers = (function() {
  'use strict';

  var DOM = null;
  var UI = null;
  var RowOps = null;
  var Variants = null;
  var DescSeo = null;
  var Images = null;
  var pendingRemovalRow = null;
  var pendingBulkRemoval = false;
  var currentBulkField = null;

  function init(domHelpers, uiUpdates, rowOperations, variantManager, descriptionSeoManager, imageManager) {
    DOM = domHelpers;
    UI = uiUpdates;
    RowOps = rowOperations;
    Variants = variantManager;
    DescSeo = descriptionSeoManager;
    Images = imageManager || null;
  }

  // ========== Modal Management ==========

  function showRemoveConfirm(message, row) {
    var modal = DOM.getModal('remove-row-confirm-modal');
    if (!modal) {
      console.error('Modal not found with ID: remove-row-confirm-modal');
      return;
    }

    var messageElement = document.getElementById('remove-row-confirm-message');
    if (messageElement) {
      messageElement.textContent = message;
    }
    
    modal.style.display = 'flex';
    pendingRemovalRow = row || null;
  }

  function hideRemoveConfirm() {
    var modal = DOM.getModal('remove-row-confirm-modal');
    if (!modal) return;

    modal.style.display = 'none';
    pendingRemovalRow = null;
    pendingBulkRemoval = false;
  }

  // ========== Bulk Apply Modal (Create tab) ==========

  function openBulkApplyModal(field) {
    var modal = document.getElementById('bulk-apply-modal');
    if (!modal) return;

    currentBulkField = field;

    modal.querySelectorAll('.bulk-field-section').forEach(function(s) {
      s.style.display = 'none';
    });
    var section = document.getElementById('bulk-field-' + field);
    if (section) section.style.display = 'block';

    var checkedCount = document.querySelectorAll('[data-role="row-select"]:checked').length;
    var scopeLabel = document.getElementById('bulk-apply-scope-label');
    if (scopeLabel) {
      scopeLabel.textContent = checkedCount > 0
        ? 'Apply to ' + checkedCount + ' selected row(s)'
        : 'Apply to all rows (none selected)';
    }

    var labels = {
      available_on: 'Set Available On',
      shipping_category: 'Set Shipping Category',
      vendor: 'Set Vendor',
      taxons: 'Set Taxons'
    };
    var titleEl = document.getElementById('bulk-apply-modal-title');
    if (titleEl) titleEl.textContent = labels[field] || 'Set Value';

    if (field === 'available_on' && window.flatpickr) {
      var avInput = document.getElementById('bulk-value-available-on');
      if (avInput) {
        if (avInput._flatpickr) avInput._flatpickr.destroy();
        flatpickr(avInput, { dateFormat: 'Y-m-d', allowInput: true });
      }
    } else if (field === 'taxons') {
      var taxonBulkSel = document.getElementById('bulk-value-taxons');
      if (taxonBulkSel && window.jQuery && jQuery.fn.select2) {
        if (!jQuery(taxonBulkSel).data('select2')) {
          var token = (window.Spree && window.Spree.api_key) || '';
          jQuery(taxonBulkSel).select2({
            width: '100%',
            placeholder: 'Search taxons\u2026',
            minimumInputLength: 1,
            dropdownParent: jQuery('#bulk-apply-modal'),
            ajax: {
              url: '/api/v1/taxons',
              dataType: 'json',
              delay: 300,
              data: function(params) {
                return {
                  per_page: 50,
                  without_children: true,
                  q: { name_cont: params.term },
                  token: token
                };
              },
              processResults: function(data) {
                return {
                  results: (data.taxons || []).map(function(t) {
                    return { id: t.id, text: t.pretty_name };
                  })
                };
              },
              cache: true
            }
          });
        }
      }
    } else if (field === 'vendor') {
      var vendorBulkSel = document.getElementById('bulk-value-vendor');
      if (vendorBulkSel && window.jQuery && jQuery.fn.select2) {
        if (!jQuery(vendorBulkSel).data('select2')) {
          jQuery(vendorBulkSel).select2({
            width: '100%',
            placeholder: 'Search vendors\u2026',
            allowClear: true,
            minimumInputLength: 1,
            dropdownParent: jQuery('#bulk-apply-modal'),
            ajax: {
              url: '/admin/product_import_files/vendors',
              dataType: 'json',
              delay: 250,
              data: function(params) {
                return { q: { name_cont: params.term } };
              },
              processResults: function(data) {
                return {
                  results: (Array.isArray(data) ? data : (data.vendors || [])).map(function(v) {
                    return { id: v.id, text: v.name };
                  })
                };
              },
              cache: true
            }
          });
        }
      }
    } else if (window.jQuery) {
      var fieldSection = document.getElementById('bulk-field-' + field);
      if (fieldSection) {
        jQuery(fieldSection).find('select').each(function() {
          if (!jQuery(this).data('select2')) {
            jQuery(this).select2({ width: '100%', dropdownParent: jQuery('#bulk-apply-modal') });
          }
        });
      }
    }

    modal.style.display = 'flex';
  }

  function closeBulkApplyModal() {
    var modal = document.getElementById('bulk-apply-modal');
    if (modal) modal.style.display = 'none';
    currentBulkField = null;
  }

  function applyBulkValue() {
    if (!currentBulkField) return;

    var table = DOM.getTable();
    if (!table) { closeBulkApplyModal(); return; }

    var checkedBoxes = document.querySelectorAll('[data-role="row-select"]:checked');
    var rowIndices = [];
    if (checkedBoxes.length > 0) {
      checkedBoxes.forEach(function(cb) {
        var row = cb.closest('tr[data-row-index]');
        if (row) rowIndices.push(row.dataset.rowIndex);
      });
    } else {
      table.querySelectorAll('tr.product-import-row[data-row-index]').forEach(function(row) {
        rowIndices.push(row.dataset.rowIndex);
      });
    }

    rowIndices.forEach(function(index) {
      var detailsRow = table.querySelector('tr.product-import-row-details[data-row-index="' + index + '"]');
      if (!detailsRow) return;

      if (currentBulkField === 'available_on') {
        var avInput = document.getElementById('bulk-value-available-on');
        if (!avInput) return;
        var wrapper = detailsRow.querySelector('.datepicker[data-wrap]');
        if (wrapper && wrapper._flatpickr) {
          wrapper._flatpickr.setDate(avInput.value, true);
        } else {
          var target = detailsRow.querySelector('[data-role="row-available-on-input"]');
          if (target) target.value = avInput.value;
        }
      } else if (currentBulkField === 'shipping_category') {
        var scSelect = detailsRow.querySelector('[data-role="row-shipping-category-select"]');
        var scValue = document.getElementById('bulk-value-shipping-category');
        if (scSelect && scValue) {
          scSelect.value = scValue.value;
          if (window.jQuery) jQuery(scSelect).trigger('change');
        }
      } else if (currentBulkField === 'vendor') {
        var vendorBulkModal = document.getElementById('bulk-value-vendor');
        var vendorRowSel = detailsRow.querySelector('[data-role="row-vendor-select"]');
        if (vendorBulkModal && vendorRowSel) {
          var selectedVendorOpts = Array.from(vendorBulkModal.selectedOptions);
          if (selectedVendorOpts.length > 0 && selectedVendorOpts[0].value) {
            var vOpt = selectedVendorOpts[0];
            if (!vendorRowSel.querySelector('option[value="' + vOpt.value + '"]')) {
              var newVOpt = new Option(vOpt.text, vOpt.value, true, true);
              vendorRowSel.appendChild(newVOpt);
            } else {
              vendorRowSel.querySelector('option[value="' + vOpt.value + '"]').selected = true;
            }
            if (window.jQuery) jQuery(vendorRowSel).trigger('change');
          } else {
            if (window.jQuery) {
              jQuery(vendorRowSel).val('').trigger('change');
            } else {
              vendorRowSel.value = '';
            }
          }
        }
      } else if (currentBulkField === 'taxons') {
        var taxonMulti = document.getElementById('bulk-value-taxons');
        if (!taxonMulti) return;
        var selectedOptions = Array.from(taxonMulti.selectedOptions);
        var taxonSelect = detailsRow.querySelector('[data-role="row-taxons-select"]');
        if (taxonSelect && selectedOptions.length > 0) {
          selectedOptions.forEach(function(opt) {
            // Add the option to the row select if it isn't already there
            if (!taxonSelect.querySelector('option[value="' + opt.value + '"]')) {
              var newOpt = new Option(opt.text, opt.value, true, true);
              taxonSelect.appendChild(newOpt);
            } else {
              taxonSelect.querySelector('option[value="' + opt.value + '"]').selected = true;
            }
          });
          if (window.jQuery) jQuery(taxonSelect).trigger('change');
        }
      }
    });

    closeBulkApplyModal();
  }

  // ========== Table Event Handlers ==========

  function handleTableClick(event) {
    var target = event.target.closest('[data-action]');
    if (!target) return;

    var action = target.getAttribute('data-action');

    if (action === 'toggle-row') {
      event.preventDefault();
      var row = target.closest('tr[data-row-index]');
      if (row) {
        var index = row.dataset.rowIndex;
        RowOps.toggleDetails(index, target);
      }
    } else if (action === 'toggle-all') {
      event.preventDefault();
      var currentState = target.getAttribute('data-state');
      if (currentState === 'expanded') {
        RowOps.collapseAll();
        UI.updateToggleAllButton('collapsed');
      } else {
        RowOps.expandAll();
        UI.updateToggleAllButton('expanded');
      }
    }
    // Note: Modal buttons are handled by document-level delegation below
  }

  function handleRemoveRow(event) {
    event.preventDefault();
    event.stopPropagation();
    
    var button = event.target.closest('[data-action="remove-row"]');
    if (!button) return;

    var detailsRow = button.closest('tr.product-import-row-details');
    if (!detailsRow) return;
    
    var rowIndex = detailsRow.dataset.rowIndex;
    if (!rowIndex) return;
    
    var parts = DOM.rowParts(rowIndex);
    var nameInput = parts.details ? parts.details.querySelector('[data-role="row-name-input"]') : null;
    var productName = nameInput && nameInput.value ? nameInput.value : 'Product ' + (parseInt(rowIndex, 10) + 1);

    showRemoveConfirm('Are you sure you want to remove "' + productName + '"?', parts.summary);
  }

  function handleRemoveSelected(event) {
    event.preventDefault();
    var count = DOM.getCheckedCount();
    if (count === 0) return;

    pendingBulkRemoval = true;
    showRemoveConfirm('Are you sure you want to remove ' + count + ' selected row(s)?', null);
  }

  function handleSelectAllChange(event) {
    var isChecked = event.target.checked;
    DOM.getSelectedCheckboxes().forEach(function(checkbox) {
      checkbox.checked = isChecked;
    });
    UI.updateSelectAllState();
  }

  function handleRowSelectChange() {
    UI.updateSelectAllState();
  }

  function handleAddRow(event) {
    event.preventDefault();
    RowOps.addRow();
  }

  // ========== Modal Event Handlers ==========

  function handleModalActions(event) {
    var target = event.target.closest('[data-action]');
    if (!target) return;

    var action = target.getAttribute('data-action');

    if (action === 'confirm-remove') {
      event.preventDefault();
      if (pendingBulkRemoval) {
        RowOps.removeSelectedRows();
      } else if (pendingRemovalRow) {
        RowOps.removeRow(pendingRemovalRow);
      }
      hideRemoveConfirm();
    } else if (action === 'cancel-remove') {
      event.preventDefault();
      hideRemoveConfirm();
    }
  }

  function handleOpenVariantModal(event) {
    var target = event.target.closest('[data-action="open-variant-modal"]');
    if (!target) return;
    
    console.log('Opening Variant modal...');
    event.preventDefault();
    event.stopPropagation(); // Prevent section toggle
    var rowIndex = target.getAttribute('data-row-index');
    if (rowIndex) Variants.openVariantModal(rowIndex);
  }

  function handleCloseVariantModal(event) {
    event.preventDefault();
    Variants.closeVariantModal();
  }

  function handleAddModalVariant(event) {
    event.preventDefault();
    Variants.addModalVariant();
  }

  function handleRemoveModalVariant(event) {
    var target = event.target.closest('[data-action="remove-modal-variant"]');
    if (!target) return;
    
    event.preventDefault();
    var variantId = parseInt(target.getAttribute('data-variant-id'), 10);
    if (variantId) Variants.removeModalVariant(variantId);
  }

  function handleSaveVariants(event) {
    event.preventDefault();
    Variants.saveVariantsToRow();
  }

  function handleOptionTypesSearch() {
    Variants.filterOptionTypes();
  }

  function handleClearOptionTypesSearch(event) {
    event.preventDefault();
    Variants.clearOptionTypesSearch();
  }

  function handleVariantModalChange(event) {
    var target = event.target;
    
    if (target.classList.contains('modal-option-type-checkbox')) {
      Variants.handleModalOptionTypeChange(target);
    } else if (target.classList.contains('modal-variant-field')) {
      Variants.handleModalVariantFieldChange(target);
    }
  }

  // ========== Description & SEO Modal Handlers ==========

  function handleOpenDescriptionSeoModal(event) {
    var target = event.target.closest('[data-action="open-description-seo-modal"]');
    if (!target) return;
    
    console.log('Opening Description/SEO modal...');
    event.preventDefault();
    event.stopPropagation(); // Prevent section toggle
    var rowIndex = target.getAttribute('data-row-index');
    if (rowIndex) DescSeo.openModal(rowIndex);
  }

  function handleCloseDescriptionSeoModal(event) {
    event.preventDefault();
    DescSeo.closeModal();
  }

  function handleSaveDescriptionSeo(event) {
    event.preventDefault();
    DescSeo.saveData();
  }

  function handleToggleDescriptionSeoSection(event) {
    var target = event.target.closest('[data-action="toggle-description-seo-section"]');
    if (!target) return;
    
    var rowIndex = target.getAttribute('data-row-index');
    if (rowIndex) DescSeo.toggleSection(rowIndex);
  }

  function handleToggleVariantsSection(event) {
    var target = event.target.closest('[data-action="toggle-variants-section"]');
    if (!target) return;
    
    var rowIndex = target.getAttribute('data-row-index');
    if (!rowIndex) return;
    
    var content = DOM.querySelector('[data-role="variants-content"][data-row-index="' + rowIndex + '"]');
    var chevron = DOM.querySelector('[data-action="toggle-variants-section"][data-row-index="' + rowIndex + '"] [data-role="variants-chevron"]');
    
    if (!content) return;
    
    var isVisible = content.style.display !== 'none';
    content.style.display = isVisible ? 'none' : 'block';
    
    if (chevron) {
      chevron.style.transform = isVisible ? 'rotate(0deg)' : 'rotate(90deg)';
    }
  }

  // ========== Images Modal Handlers ==========

  function handleOpenImagesModal(event) {
    var target = event.target.closest('[data-action="open-images-modal"]');
    if (!target) return;

    event.preventDefault();
    event.stopPropagation();
    var rowIndex = target.getAttribute('data-row-index');
    if (rowIndex && Images) Images.openModal(rowIndex);
  }

  function handleCloseImagesModal(event) {
    event.preventDefault();
    if (Images) Images.closeModal();
  }

  function handleAddModalImage(event) {
    event.preventDefault();
    if (Images) Images.addImageToQueue();
  }

  function handleRemoveModalImage(event) {
    var target = event.target.closest('[data-action="remove-modal-image"]');
    if (!target) return;
    event.preventDefault();
    var imageId = parseInt(target.getAttribute('data-image-id'), 10);
    if (imageId && Images) Images.removeImageFromQueue(imageId);
  }

  function handleSaveImages(event) {
    event.preventDefault();
    if (Images) Images.saveImagesToRow();
  }

  function handleToggleImagesSection(event) {
    var target = event.target.closest('[data-action="toggle-images-section"]');
    if (!target) return;
    var rowIndex = target.getAttribute('data-row-index');
    if (rowIndex && Images) Images.toggleSection(rowIndex);
  }

  // ========== Event Attachment ==========

  function attachEventListeners() {
    console.log('Attaching event listeners...');
    var table = DOM.getTable();
    if (!table) return;

    // Table interactions (using delegation)
    table.addEventListener('click', handleTableClick);
    
    // Remove row button - use simple delegation on document
    document.addEventListener('click', function(event) {
      var removeBtn = event.target.closest('[data-action="remove-row"]');
      if (removeBtn) {
        var isInTable = removeBtn.closest('#product-import-table');
        if (isInTable) {
          handleRemoveRow(event);
        }
      }
    });

    // Header controls
    var selectAll = DOM.querySelector('[data-role="select-all"]');
    if (selectAll) {
      selectAll.addEventListener('change', handleSelectAllChange);
    }

    table.addEventListener('change', function(event) {
      if (event.target.matches('[data-role="row-select"]')) {
        handleRowSelectChange();
      }
    });

    var removeSelectedBtn = DOM.querySelector('[data-action="remove-selected"]');
    if (removeSelectedBtn) {
      removeSelectedBtn.addEventListener('click', handleRemoveSelected);
    }

    // Add row button
    var addRowBtn = document.querySelector('[data-action="add-row"]');
    if (addRowBtn) {
      addRowBtn.addEventListener('click', handleAddRow);
    }

    // Remove confirmation modal
    var removeModal = DOM.getModal('remove-row-confirm-modal');
    if (removeModal) {
      removeModal.addEventListener('click', handleModalActions);
    }

    // Variant modal
    var variantModal = DOM.getModal('variant-modal');
    console.log('Variant modal found:', !!variantModal);
    if (variantModal) {
      // Close buttons
      variantModal.addEventListener('click', function(event) {
        if (event.target.matches('[data-action="close-variant-modal"]') || 
            event.target.closest('[data-action="close-variant-modal"]')) {
          handleCloseVariantModal(event);
        }
      });

      // Backdrop click to close
      variantModal.addEventListener('click', function(event) {
        if (event.target === variantModal) {
          handleCloseVariantModal(event);
        }
      });

      // Add variant button
      variantModal.addEventListener('click', function(event) {
        if (event.target.matches('[data-action="add-modal-variant"]') ||
            event.target.closest('[data-action="add-modal-variant"]')) {
          handleAddModalVariant(event);
        }
      });

      // Remove variant button
      variantModal.addEventListener('click', function(event) {
        var removeBtn = event.target.closest('[data-action="remove-modal-variant"]');
        if (removeBtn) {
          handleRemoveModalVariant(event);
        }
      });

      // Save button
      variantModal.addEventListener('click', function(event) {
        if (event.target.matches('[data-action="save-variants"]') ||
            event.target.closest('[data-action="save-variants"]')) {
          handleSaveVariants(event);
        }
      });

      // Toggle variant card collapse
      variantModal.addEventListener('click', function(event) {
        var toggleBtn = event.target.closest('[data-action="toggle-variant-card"]');
        if (toggleBtn) {
          event.preventDefault();
          var variantId = parseInt(toggleBtn.getAttribute('data-variant-id'), 10);
          if (variantId) Variants.toggleVariantCard(variantId);
        }
      });

      // Option types search
      var searchInput = document.getElementById('option-types-search');
      if (searchInput) {
        searchInput.addEventListener('input', handleOptionTypesSearch);
      }

      var clearSearchBtn = document.getElementById('clear-option-types-search');
      if (clearSearchBtn) {
        clearSearchBtn.addEventListener('click', handleClearOptionTypesSearch);
      }

      // Modal field changes
      variantModal.addEventListener('change', handleVariantModalChange);
      variantModal.addEventListener('input', function(event) {
        if (event.target.classList.contains('modal-variant-field')) {
          Variants.handleModalVariantFieldChange(event.target);
        }
      });
    }

    // Description & SEO modal
    var descSeoModal = DOM.getModal('description-seo-modal');
    console.log('Description/SEO modal found:', !!descSeoModal);
    if (descSeoModal) {
      // Close buttons
      descSeoModal.addEventListener('click', function(event) {
        if (event.target.matches('[data-action="close-description-seo-modal"]') || 
            event.target.closest('[data-action="close-description-seo-modal"]')) {
          handleCloseDescriptionSeoModal(event);
        }
      });

      // Backdrop click to close
      descSeoModal.addEventListener('click', function(event) {
        if (event.target === descSeoModal) {
          handleCloseDescriptionSeoModal(event);
        }
      });

      // Save button
      descSeoModal.addEventListener('click', function(event) {
        if (event.target.matches('[data-action="save-description-seo"]') ||
            event.target.closest('[data-action="save-description-seo"]')) {
          handleSaveDescriptionSeo(event);
        }
      });
    }

    // Bulk Apply Modal listeners
    document.addEventListener('click', function(event) {
      if (event.target.closest('[data-action="open-bulk-apply"]')) {
        var btn = event.target.closest('[data-action="open-bulk-apply"]');
        event.preventDefault();
        openBulkApplyModal(btn.getAttribute('data-field'));
        return;
      }
      if (event.target.closest('[data-action="close-bulk-apply-modal"]') ||
          event.target.closest('[data-action="cancel-bulk-apply"]')) {
        event.preventDefault();
        closeBulkApplyModal();
        return;
      }
      if (event.target.closest('[data-action="confirm-bulk-apply"]')) {
        event.preventDefault();
        applyBulkValue();
        return;
      }
    });
    var bulkApplyModal = document.getElementById('bulk-apply-modal');
    if (bulkApplyModal) {
      bulkApplyModal.addEventListener('click', function(event) {
        if (event.target === bulkApplyModal) closeBulkApplyModal();
      });
    }

    // Section toggles and modal buttons (using document delegation for dynamically added rows)
    console.log('Adding document-level click listeners for modals and sections');
    document.addEventListener('click', function(event) {
      var target = event.target;
      console.log('Document click detected:', target);
      
      // Check modal buttons FIRST (more specific) before section toggles
      if (event.target.closest('[data-action="open-description-seo-modal"]')) {
        console.log('Open description/SEO modal button clicked');
        handleOpenDescriptionSeoModal(event);
      } else if (event.target.closest('[data-action="open-variant-modal"]')) {
        console.log('Open variant modal button clicked');
        handleOpenVariantModal(event);
      } else if (event.target.closest('[data-action="open-images-modal"]')) {
        handleOpenImagesModal(event);
      } else if (event.target.closest('[data-action="toggle-description-seo-section"]')) {
        console.log('Toggle description/SEO section clicked');
        handleToggleDescriptionSeoSection(event);
      } else if (event.target.closest('[data-action="toggle-variants-section"]')) {
        console.log('Toggle variants section clicked');
        handleToggleVariantsSection(event);
      } else if (event.target.closest('[data-action="toggle-images-section"]')) {
        handleToggleImagesSection(event);
      }
    });

    // Images modal
    var imagesModal = document.getElementById('images-modal');
    if (imagesModal) {
      imagesModal.addEventListener('click', function(event) {
        if (event.target === imagesModal) { handleCloseImagesModal(event); return; }
        if (event.target.closest('[data-action="close-images-modal"]')) { handleCloseImagesModal(event); return; }
        if (event.target.closest('[data-action="add-modal-image"]')) { handleAddModalImage(event); return; }
        if (event.target.closest('[data-action="remove-modal-image"]')) { handleRemoveModalImage(event); return; }
        if (event.target.closest('[data-action="save-images"]')) { handleSaveImages(event); return; }
      });
    }
  }

  return {
    init: init,
    attachEventListeners: attachEventListeners
  };
})();
