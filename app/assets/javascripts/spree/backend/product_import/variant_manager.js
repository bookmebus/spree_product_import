/**
 * Variant Manager
 * Handles variant modal, option types, and variant creation/editing
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.VariantManager = (function() {
  'use strict';

  var DOM = null;
  var currentEditingRowIndex = null;
  var modalVariants = [];
  var modalOptionTypes = [];
  var optionTypesData = [];

  // Lazy-fetch state for option types
  var optionTypesFetched = false;
  var optionTypesFetching = false;

  // Per-row form-field base override
  var rowFormBases = {};

  function registerRowFormBase(rowIndex, base) {
    rowFormBases[rowIndex] = base;
  }

  function init(domHelpers) {
    DOM = domHelpers;
  }

  function setOptionTypesData(data) {
    optionTypesData = data || [];
  }

  // ========== Modal Management ==========

  function openVariantModal(rowIndex) {
    currentEditingRowIndex = rowIndex;
    var modal = DOM.getModal('variant-modal');
    if (!modal) return;

    loadExistingVariantData(rowIndex);
    modal.style.display = 'flex';

    if (optionTypesFetched) {
      renderModalVariants();
      initOptionTypesSearch();
    } else if (!optionTypesFetching) {
      fetchOptionTypes(function() {
        renderModalVariants();
        initOptionTypesSearch();
      });
    }
  }

  function closeVariantModal() {
    var modal = DOM.getModal('variant-modal');
    if (!modal) return;
    
    modal.style.display = 'none';
    currentEditingRowIndex = null;
    modalVariants = [];
    modalOptionTypes = [];
    clearModalState();
  }

  function clearModalState() {
    document.querySelectorAll('.modal-option-type-checkbox').forEach(function(cb) {
      cb.checked = false;
    });
    
    var container = document.getElementById('modal-variants-container');
    if (container) {
      container.innerHTML = '<p class="text-muted text-center" id="no-variants-message">No variants added yet. Click "Add Variant" to create one.</p>';
    }
    
    clearOptionTypesSearch();
  }

  // ========== Option Types Lazy Fetch ==========

  function fetchOptionTypes(callback) {
    optionTypesFetching = true;
    var container = document.getElementById('modal-option-types-container');
    if (container) {
      container.innerHTML = '<p class="text-center text-muted py-3">Loading option types\u2026</p>';
    }

    jQuery.getJSON('/admin/product_import_files/option_types', function(data) {
      optionTypesFetched = true;
      optionTypesFetching = false;
      optionTypesData = data || [];
      renderOptionTypeCheckboxes(optionTypesData);
      // Restore any already-loaded option type selections
      modalOptionTypes.forEach(function(otId) {
        var cb = document.querySelector('.modal-option-type-checkbox[data-option-type-id="' + otId + '"]');
        if (cb) cb.checked = true;
      });
      if (typeof callback === 'function') callback();
    }).fail(function() {
      optionTypesFetching = false;
      if (container) {
        container.innerHTML = '<p class="text-center text-danger py-3">Failed to load option types.</p>';
      }
    });
  }

  function renderOptionTypeCheckboxes(data) {
    var container = document.getElementById('modal-option-types-container');
    if (!container) return;

    if (!data || data.length === 0) {
      container.innerHTML = '<p class="text-center text-muted py-3">No option types found.</p>';
      return;
    }

    var html = '';
    data.forEach(function(ot) {
      var safeId        = String(ot.id);
      var safeName      = String(ot.name || '').replace(/"/g, '&quot;').replace(/</g, '&lt;');
      var safePresent   = String(ot.presentation || '').replace(/"/g, '&quot;').replace(/</g, '&lt;');
      html += '<div class="custom-control custom-checkbox mb-2 option-type-item"' +
              ' data-option-type-name="' + safeName.toLowerCase() + '"' +
              ' data-option-type-presentation="' + safePresent.toLowerCase() + '">' +
              '<input type="checkbox" class="custom-control-input modal-option-type-checkbox"' +
              ' id="modal_option_type_' + safeId + '"' +
              ' value="' + safeId + '"' +
              ' data-option-type-id="' + safeId + '"' +
              ' data-option-type-name="' + safeName + '"' +
              ' data-option-type-presentation="' + safePresent + '">' +
              '<label class="custom-control-label" for="modal_option_type_' + safeId + '">' +
              safePresent + '</label>' +
              '</div>';
    });
    container.innerHTML = html;
  }

  // ========== Option Types Search ==========

  function initOptionTypesSearch() {
    updateOptionTypesCount();
  }

  function filterOptionTypes() {
    var searchInput = document.getElementById('option-types-search');
    if (!searchInput) return;
    
    var query = searchInput.value.toLowerCase().trim();
    var items = document.querySelectorAll('.option-type-item');
    var noResults = document.getElementById('no-option-types-found');
    var clearBtn = document.getElementById('clear-option-types-search');
    var visibleCount = 0;
    
    if (clearBtn) {
      clearBtn.style.display = query ? 'block' : 'none';
    }
    
    items.forEach(function(item) {
      var name = item.getAttribute('data-option-type-name') || '';
      var presentation = item.getAttribute('data-option-type-presentation') || '';
      
      if (!query || name.indexOf(query) > -1 || presentation.indexOf(query) > -1) {
        item.style.display = '';
        visibleCount++;
      } else {
        item.style.display = 'none';
      }
    });
    
    if (noResults) {
      noResults.style.display = visibleCount === 0 && items.length > 0 ? 'block' : 'none';
    }
    
    updateOptionTypesCount();
  }

  function clearOptionTypesSearch() {
    var searchInput = document.getElementById('option-types-search');
    var clearBtn = document.getElementById('clear-option-types-search');
    
    if (searchInput) searchInput.value = '';
    if (clearBtn) clearBtn.style.display = 'none';
    
    document.querySelectorAll('.option-type-item').forEach(function(item) {
      item.style.display = '';
    });
    
    var noResults = document.getElementById('no-option-types-found');
    if (noResults) noResults.style.display = 'none';
    
    updateOptionTypesCount();
  }

  function updateOptionTypesCount() {
    var countDisplay = document.getElementById('option-types-count');
    if (!countDisplay) return;
    
    var items = document.querySelectorAll('.option-type-item');
    var visibleItems = Array.from(items).filter(function(item) {
      return item.style.display !== 'none';
    });
    
    var total = items.length;
    var visible = visibleItems.length;
    
    if (visible === total) {
      countDisplay.textContent = total + ' option type' + (total !== 1 ? 's' : '');
    } else {
      countDisplay.textContent = 'Showing ' + visible + ' of ' + total;
    }
  }

  // ========== Variant Data Management ==========

  function loadExistingVariantData(rowIndex) {
    var dataContainer = document.querySelector('[data-role="variants-data"][data-row-index="' + rowIndex + '"]');
    if (!dataContainer) return;

    try {
      var data = dataContainer.getAttribute('data-variants');
      if (!data) return;
      
      var parsed = JSON.parse(data);
      modalVariants = parsed.variants || [];
      modalOptionTypes = parsed.option_types || [];
      
      modalOptionTypes.forEach(function(otId) {
        var checkbox = document.querySelector('.modal-option-type-checkbox[data-option-type-id="' + otId + '"]');
        if (checkbox) checkbox.checked = true;
      });
    } catch (e) {
      console.error('Error loading variant data:', e);
    }
  }

  function addModalVariant() {
    var selectedOptionTypes = getSelectedOptionTypes();
    
    if (selectedOptionTypes.length === 0) {
      alert('Please select at least one option type first.');
      return;
    }

    var variant = {
      id: Date.now(),
      option_values: {},
      sku: '',
      price: '',
      compare_at_price: '',
      cost_price: '',
      weight: '',
      height: '',
      width: '',
      depth: ''
    };

    modalVariants.push(variant);
    renderModalVariants();
  }

  function removeModalVariant(variantId) {
    modalVariants = modalVariants.filter(function(v) { return v.id !== variantId; });
    renderModalVariants();
  }

  function getSelectedOptionTypes() {
    var selected = [];
    document.querySelectorAll('.modal-option-type-checkbox:checked').forEach(function(cb) {
      selected.push({
        id: cb.getAttribute('data-option-type-id'),
        name: cb.getAttribute('data-option-type-name'),
        presentation: cb.getAttribute('data-option-type-presentation')
      });
    });
    return selected;
  }

  function updateModalVariantData(variantId, field, value) {
    var variant = modalVariants.find(function(v) { return v.id === variantId; });
    if (variant) variant[field] = value;
  }

  function updateModalVariantOptionValue(variantId, optionTypeId, optionValueId) {
    var variant = modalVariants.find(function(v) { return v.id === variantId; });
    if (variant) variant.option_values[optionTypeId] = optionValueId;
  }

  // ========== Variant Rendering ==========

  function renderModalVariants() {
    var container = document.getElementById('modal-variants-container');
    if (!container) return;

    var noMessage = document.getElementById('no-variants-message');
    
    if (modalVariants.length === 0) {
      if (!noMessage) {
        container.innerHTML = '<p class="text-muted text-center" id="no-variants-message">No variants added yet. Click "Add Variant" to create one.</p>';
      }
      return;
    }

    if (noMessage) noMessage.remove();

    container.innerHTML = '';
    var selectedOptionTypes = getSelectedOptionTypes();

    modalVariants.forEach(function(variant, index) {
      var variantCard = createModalVariantCard(variant, index, selectedOptionTypes);
      container.appendChild(variantCard);
    });

    initializeVariantWidgets(container);
  }

  function createModalVariantCard(variant, index, selectedOptionTypes) {
    var card = document.createElement('div');
    card.className = 'card mb-3';
    card.setAttribute('data-variant-id', variant.id);

    var headerHtml = buildCardHeader(variant, index);
    var bodyHtml = buildCardBody(variant, selectedOptionTypes);

    card.innerHTML = headerHtml + bodyHtml;
    return card;
  }

  function buildCardHeader(variant, index) {
    var collapseId = 'collapse-variant-' + variant.id;
    var chevronSvg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="12px" height="12px" viewBox="0 0 2134 2134" version="1.1" xml:space="preserve" style="fill-rule:evenodd;clip-rule:evenodd;stroke-linejoin:round;stroke-miterlimit:2;" class="icon-chevron-right">' +
      '<path fill="currentColor" d="M1571.72,1023.16l-923.077,-923.077c-24.039,-24.038 -62.981,-24.038 -87.019,0c-24.039,24.039 -24.039,62.981 0,87.019l879.567,879.568l-879.567,879.567c-24.039,24.039 -24.039,62.981 0,87.019c12.019,12.02 27.724,18.029 43.509,18.029c15.785,0 31.491,-6.009 43.51,-18.029l923.077,-923.077c24.038,-24.038 24.038,-62.98 0,-87.019Z" style="fill-rule:nonzero;stroke:currentColor;stroke-width:75px;"></path>' +
      '</svg>';
    
    // Only show delete button for new variants (without db_id)
    var deleteButton = '';
    if (!variant.db_id) {
      deleteButton = '<button type="button" class="btn btn-sm btn-danger" data-action="remove-modal-variant" data-variant-id="' + variant.id + '">' +
        '<span class="icon icon-trash"></span>' +
      '</button>';
    }
    
    return '<div class="card-header d-flex justify-content-between align-items-center">' +
      '<button class="btn btn-link p-0 text-left flex-grow-1 text-decoration-none" type="button" data-action="toggle-variant-card" data-variant-id="' + variant.id + '" data-collapse-target="' + collapseId + '" style="color: inherit;">' +
        '<div class="d-flex align-items-center" style="gap: 8px;">' +
          '<span data-role="variant-card-chevron" style="display: inline-block; transform: rotate(90deg); transition: transform 0.2s;">' + chevronSvg + '</span>' +
          '<h6 class="mb-0">Variant ' + (index + 1) + '</h6>' +
        '</div>' +
      '</button>' +
      deleteButton +
    '</div>';
  }

  function buildCardBody(variant, selectedOptionTypes) {
    var collapseId = 'collapse-variant-' + variant.id;
    var html = '<div id="' + collapseId + '" style="display: block;">';
    html += '<div class="card-body">';
    html += buildOptionValuesSection(variant, selectedOptionTypes);
    html += '<hr>';
    html += '<h6 class="mb-3">Variant Details</h6>';
    html += buildVariantFieldsSection(variant);
    html += '</div>';
    html += '</div>';
    return html;
  }

  function buildOptionValuesSection(variant, selectedOptionTypes) {
    var html = '<div class="row">';
    
    selectedOptionTypes.forEach(function(optionType) {
      var optType = optionTypesData.find(function(ot) { return ot.id.toString() === optionType.id; });
      if (!optType) return;

      html += '<div class="col-12 col-md-6 mb-3">';
      html += '<label>' + optionType.presentation + ' <span class="text-danger">*</span></label>';
      html += '<select class="select2-clear modal-variant-option-value" data-variant-id="' + variant.id + '" data-option-type-id="' + optionType.id + '">';
      html += '<option value="">Select ' + optionType.presentation + '</option>';
      
      optType.option_values.forEach(function(ov) {
        var selected = variant.option_values[optionType.id] == ov.id ? 'selected' : '';
        html += '<option value="' + ov.id + '" ' + selected + '>' + ov.presentation + '</option>';
      });
      
      html += '</select>';
      html += '</div>';
    });
    
    html += '</div>';
    return html;
  }

  function buildVariantFieldsSection(variant) {
    var fields = [
      { name: 'sku', label: 'SKU', required: false },
      { name: 'price', label: 'Price', required: true },
      { name: 'compare_at_price', label: 'Compare At Price', required: false },
      { name: 'cost_price', label: 'Cost Price', required: false },
      { name: 'weight', label: 'Weight', required: false },
      { name: 'height', label: 'Height', required: false },
      { name: 'width', label: 'Width', required: false },
      { name: 'depth', label: 'Depth', required: false }
    ];

    var html = '<div class="row">';
    
    fields.forEach(function(field) {
      html += '<div class="col-12 col-md-6 mb-3">';
      html += '<label>' + field.label;
      if (field.required) html += ' <span class="text-danger">*</span>';
      html += '</label>';
      html += '<input type="text" class="form-control modal-variant-field" ';
      html += 'data-variant-id="' + variant.id + '" ';
      html += 'data-field="' + field.name + '" ';
      html += 'value="' + (variant[field.name] || '') + '"';
      if (field.required) html += ' required';
      html += '>';
      html += '</div>';
    });
    
    html += '</div>';
    return html;
  }

  function initializeVariantWidgets(container) {
    if (window.jQuery) {
      jQuery(container).find('select.select2').select2({ 
        width: '100%',
        dropdownParent: jQuery('#variant-modal')
      });
      jQuery(container).find('select.select2-clear').select2({ 
        width: '100%', 
        allowClear: true,
        dropdownParent: jQuery('#variant-modal')
      });
      
      jQuery(container).find('select.modal-variant-option-value').on('change', function() {
        var variantId = parseInt(jQuery(this).attr('data-variant-id'), 10);
        var optionTypeId = jQuery(this).attr('data-option-type-id');
        updateModalVariantOptionValue(variantId, optionTypeId, jQuery(this).val());
      });
    }
    
    if (window.flatpickr) {
      container.querySelectorAll('.datepicker').forEach(function(input) {
        flatpickr(input, { 
          altFormat: 'F j, Y',
          dateFormat: 'Y-m-d'
        });
      });
    }
  }

  // ========== Save Operations ==========

  function saveVariantsToRow() {
    if (currentEditingRowIndex === null) {
      console.warn('No row being edited');
      return;
    }

    var selectedOptionTypes = getSelectedOptionTypes();
    modalOptionTypes = selectedOptionTypes.map(function(ot) { return ot.id; });

    if (!validateVariants(selectedOptionTypes)) {
      alert('Please fill in all required fields (option values and price) for all variants.');
      return;
    }

    var dataContainer = document.querySelector('[data-role="variants-data"][data-row-index="' + currentEditingRowIndex + '"]');
    if (!dataContainer) {
      console.warn('Data container not found for row:', currentEditingRowIndex);
      return;
    }

    var data = {
      option_types: modalOptionTypes,
      variants: modalVariants
    };

    dataContainer.setAttribute('data-variants', JSON.stringify(data));
    createVariantFormFields(currentEditingRowIndex, data);
    updateVariantSummary(currentEditingRowIndex, data);
    closeVariantModal();
  }

  function validateVariants(selectedOptionTypes) {
    if (modalVariants.length === 0) return true;

    // Get master product SKU from the current row
    var summaryRow = DOM.querySelector('[data-row-index="' + currentEditingRowIndex + '"][data-role="row-summary"]');
    if (!summaryRow) return true;
    
    var detailsRow = summaryRow.nextElementSibling;
    if (!detailsRow) return true;
    
    var skuInput = detailsRow.querySelector('[data-role="row-sku-input"]');
    var masterSku = skuInput ? skuInput.value.trim().toLowerCase() : '';

    // Track variant SKUs to check for duplicates
    var variantSkus = {};
    var errors = [];

    var allValid = modalVariants.every(function(variant, index) {
      // Check required fields
      var hasAllOptionValues = selectedOptionTypes.every(function(ot) {
        return variant.option_values[ot.id];
      });
      
      if (!hasAllOptionValues || !variant.price) {
        return false;
      }

      // Check SKU conflicts
      if (variant.sku) {
        var variantSkuLower = variant.sku.trim().toLowerCase();
        
        // Check if variant SKU matches master product SKU
        if (masterSku && variantSkuLower === masterSku) {
          errors.push('Variant ' + (index + 1) + ': SKU "' + variant.sku + '" conflicts with master product SKU');
          return false;
        }
        
        // Check for duplicate SKUs among variants
        if (variantSkus[variantSkuLower]) {
          errors.push('Variant ' + (index + 1) + ': SKU "' + variant.sku + '" is duplicated');
          return false;
        }
        
        variantSkus[variantSkuLower] = true;
      }

      return true;
    });

    if (!allValid && errors.length > 0) {
      alert('Validation errors:\n\n' + errors.join('\n'));
      return false;
    }

    if (!allValid) {
      alert('Please fill in all required fields (option values and price) for all variants.');
      return false;
    }

    return true;
  }

  function createVariantFormFields(rowIndex, data) {
    var dataContainer = document.querySelector('[data-role="variants-data"][data-row-index="' + rowIndex + '"]');
    if (!dataContainer) {
      console.warn('Variant data container not found for row:', rowIndex);
      return;
    }

    dataContainer.innerHTML = '';

    // Registered base for update rows: 'product_updates[id][new_variants]'
    // For create rows it is:           'product_import_files[idx][variants]'
    var registeredBase = rowFormBases[rowIndex];
    
    // For create rows the row-level base (used for option_type_ids and non-variant fields)
    var rowBase        = registeredBase
                           ? registeredBase.replace(/\[new_variants\]$/, '')
                           : ('product_import_files[' + rowIndex + ']');
    // Variant array base: update rows use the registered base as-is;
    // create rows nest under [variants] so Rails permit(:variants) picks them up.
    var newVarBase     = registeredBase || (rowBase + '[variants]');
    var optTypeBase    = rowBase;
    var newVarIdx      = 0;

    // Option type IDs
    data.option_types.forEach(function(otId) {
      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = optTypeBase + '[option_type_ids][]';
      input.value = otId;
      dataContainer.appendChild(input);
    });

    data.variants.forEach(function(variant, varIdx) {
      // Variants with a db_id already exist in the DB → update them directly
      var isExisting = !!variant.db_id;
      var base;
      if (isExisting && rowBase) {
        base = rowBase + '[variants][' + variant.db_id + ']';
      } else {
        base = newVarBase + '[' + newVarIdx + ']';
        newVarIdx++;
      }

      Object.keys(variant.option_values).forEach(function(otId) {
        var input = document.createElement('input');
        input.type = 'hidden';
        input.name = base + '[option_values][' + otId + ']';
        input.value = variant.option_values[otId];
        dataContainer.appendChild(input);
      });

      ['sku', 'price', 'compare_at_price', 'cost_price', 'weight', 'height', 'width', 'depth'].forEach(function(field) {
        var val = variant[field];
        if (val !== undefined && val !== null && val !== '') {
          var input = document.createElement('input');
          input.type = 'hidden';
          input.name = base + '[' + field + ']';
          input.value = val;
          dataContainer.appendChild(input);
        }
      });
    });
  }

  // Scan all variants-data elements with pre-seeded data-variants JSON
  // (server-rendered for update mode) and render summaries + form fields.
  function initializeExistingRows() {
    document.querySelectorAll('[data-role="variants-data"]').forEach(function(container) {
      var raw = container.getAttribute('data-variants');
      if (!raw) return;
      try {
        var data = JSON.parse(raw);
        if (!data.variants || data.variants.length === 0) return;
        var rowIndex = container.getAttribute('data-row-index');
        var summaryEl = document.querySelector('[data-role="variants-summary"][data-row-index="' + rowIndex + '"]');
        if (summaryEl) {
          var html = '<div><strong>Variants:</strong> ' + data.variants.length + ' variant(s) configured</div>';
          html += '<ul class="mt-2 mb-0">';
          data.variants.slice(0, 5).forEach(function(v) { html += '<li>' + getVariantDisplayName(v) + '</li>'; });
          if (data.variants.length > 5) {
            html += '<li class="text-muted">... and ' + (data.variants.length - 5) + ' more</li>';
          }
          html += '</ul>';
          summaryEl.innerHTML = html;
        }
        createVariantFormFields(rowIndex, data);
      } catch (e) {
        console.error('Error initializing variant row:', e);
      }
    });
  }

  function updateVariantSummary(rowIndex, data) {
    var summaryContainer = document.querySelector('[data-role="variants-summary"][data-row-index="' + rowIndex + '"]');
    if (!summaryContainer) return;

    if (data.variants.length === 0) {
      summaryContainer.innerHTML = '<p class="text-muted mb-0">No variants configured</p>';
      return;
    }

    var selectedOptionTypes = getSelectedOptionTypes();
    var html = buildSummaryContent(data, selectedOptionTypes);
    summaryContainer.innerHTML = html;
  }

  function buildSummaryContent(data, selectedOptionTypes) {
    var optionTypeNames = selectedOptionTypes.map(function(ot) { return ot.presentation; }).join(', ');
    
    var html = '<div class="mb-2"><strong>Option Types:</strong> ' + optionTypeNames + '</div>';
    html += '<div><strong>Variants:</strong> ' + data.variants.length + ' variant(s) configured</div>';
    html += '<ul class="mt-2 mb-0">';
    
    data.variants.slice(0, 5).forEach(function(variant) {
      html += '<li>' + getVariantDisplayName(variant) + '</li>';
    });

    if (data.variants.length > 5) {
      html += '<li class="text-muted">... and ' + (data.variants.length - 5) + ' more</li>';
    }
    
    html += '</ul>';
    return html;
  }

  function getVariantDisplayName(variant) {
    var optionValueNames = [];
    
    Object.keys(variant.option_values).forEach(function(otId) {
      var optType = optionTypesData.find(function(ot) { return ot.id.toString() === otId; });
      if (optType) {
        var optValue = optType.option_values.find(function(ov) { 
          return ov.id.toString() === variant.option_values[otId]; 
        });
        if (optValue) {
          optionValueNames.push(optValue.presentation);
        }
      }
    });
    
    return optionValueNames.join(' / ') + (variant.sku ? ' (SKU: ' + variant.sku + ')' : '');
  }

  // ========== Event Handlers ==========

  function handleModalOptionTypeChange(checkbox) {
    if (!checkbox.checked && modalVariants.length > 0) {
      var confirmed = confirm('Unchecking this option type will remove all configured variants. Continue?');
      if (!confirmed) {
        checkbox.checked = true;
        return false;
      }
      modalVariants = [];
      renderModalVariants();
    }
    return true;
  }

  function handleModalVariantFieldChange(target) {
    if (target.classList.contains('modal-variant-field')) {
      var variantId = parseInt(target.getAttribute('data-variant-id'), 10);
      var field = target.getAttribute('data-field');
      updateModalVariantData(variantId, field, target.value);
    }
  }

  function toggleVariantCard(variantId) {
    var collapseId = 'collapse-variant-' + variantId;
    var content = document.getElementById(collapseId);
    var chevron = document.querySelector('[data-action="toggle-variant-card"][data-variant-id="' + variantId + '"] [data-role="variant-card-chevron"]');
    
    if (!content) return;
    
    var isVisible = content.style.display !== 'none';
    content.style.display = isVisible ? 'none' : 'block';
    
    if (chevron) {
      chevron.style.transform = isVisible ? 'rotate(0deg)' : 'rotate(90deg)';
    }
  }

  return {
    init: init,
    setOptionTypesData: setOptionTypesData,
    openVariantModal: openVariantModal,
    closeVariantModal: closeVariantModal,
    addModalVariant: addModalVariant,
    removeModalVariant: removeModalVariant,
    saveVariantsToRow: saveVariantsToRow,
    filterOptionTypes: filterOptionTypes,
    clearOptionTypesSearch: clearOptionTypesSearch,
    handleModalOptionTypeChange: handleModalOptionTypeChange,
    handleModalVariantFieldChange: handleModalVariantFieldChange,
    toggleVariantCard: toggleVariantCard,
    registerRowFormBase: registerRowFormBase,
    initializeExistingRows: initializeExistingRows
  };
})();
