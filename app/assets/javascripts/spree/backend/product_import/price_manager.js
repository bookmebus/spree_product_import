/**
 * Price Manager Module
 * Handles price management modal for update mode:
 *   - Opens modal with product's variants
 *   - Shows prices for each variant (master and non-master)
 *   - Allows editing price and compare_price
 *   - Saves price data to hidden form fields
 */

// Ensure Spree namespace exists
window.Spree = window.Spree || {};
window.Spree.ProductImport = window.Spree.ProductImport || {};

Spree.ProductImport.PriceManager = (function () {
  'use strict';

  // ========== State ==========
  var modal = null;
  var currentRowIndex = null;
  var priceData = {}; // { variant_id: { price, compare_price, currency } }
  var defaultCurrency = 'USD';
  var productName = '';

  // ========== Modal Management ==========

  function openPriceModal(rowIndex) {
    currentRowIndex = rowIndex;
    modal = document.getElementById('price-modal');
    if (!modal) return;

    // Get product info
    var card = document.querySelector('[data-row-index="' + rowIndex + '"]');
    if (!card) return;

    var parentCard = card.closest('.update-product-card');
    if (parentCard) {
      productName = parentCard.dataset.productName || '';
    }

    // Update modal title
    var nameEl = document.querySelector('[data-role="price-modal-product-name"]');
    if (nameEl) {
      nameEl.textContent = productName;
    }

    // Update currency info
    var currencyEl = document.querySelector('[data-role="price-modal-currency"]');
    if (currencyEl) {
      currencyEl.textContent = defaultCurrency;
    }

    // Load existing price data
    loadPriceData(rowIndex);

    // Render variants
    renderPriceVariants();

    // Show modal
    modal.style.display = 'flex';
  }

  function closePriceModal() {
    if (modal) {
      modal.style.display = 'none';
    }
    currentRowIndex = null;
    priceData = {};
  }

  // ========== Data Loading ==========

  function loadPriceData(rowIndex) {
    priceData = {};
    
    // Get price data from hidden input if exists
    var priceDataEl = document.querySelector('[data-role="price-data"][data-row-index="' + rowIndex + '"]');
    if (priceDataEl) {
      try {
        var data = JSON.parse(priceDataEl.value || '{}');
        if (data && typeof data === 'object') {
          Object.keys(data).forEach(function (variantId) {
            priceData[variantId] = {
              price: data[variantId].price || '',
              compare_price: data[variantId].compare_price || '',
              currency: data[variantId].currency || defaultCurrency
            };
          });
        }
      } catch (e) {
        console.error('Error parsing price data:', e);
      }
    }
  }

  // ========== Rendering ==========

  function renderPriceVariants() {
    var container = document.querySelector('[data-role="price-variants-container"]');
    if (!container) return;

    if (!currentRowIndex) {
      container.innerHTML = '<p class="text-muted text-center py-4">No product selected</p>';
      return;
    }

    // Get variants list from the price section
    var variantsListEl = document.querySelector('[data-role="price-variants-list"][data-row-index="' + currentRowIndex + '"]');
    if (!variantsListEl) {
      container.innerHTML = '<p class="text-muted text-center py-4">No variants data found</p>';
      return;
    }

    var variants = [];
    try {
      variants = JSON.parse(variantsListEl.value || '[]');
    } catch (e) {
      console.error('Error parsing variants list:', e);
    }

    if (variants.length === 0) {
      container.innerHTML = '<div class="alert alert-warning mb-0">' +
        '<small>No variants found.</small>' +
        '</div>';
      return;
    }

    // Render table
    var html = '<div class="table-responsive"><table class="table table-bordered table-sm">';
    html += '<colgroup>';
    html += '<col style="width: 30%">';
    html += '<col style="width: 15%">';
    html += '<col style="width: 25%">';
    html += '<col style="width: 30%">';
    html += '</colgroup>';
    html += '<thead class="thead-light">';
    html += '<tr>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('options', 'Options') : 'Options') + '</th>';
    html += '<th class="text-center">' + (window.Spree && Spree.t ? Spree.t('currency', 'Currency') : 'Currency') + '</th>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('price', 'Price') : 'Price') + '</th>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('compare_at_price', 'Compare at Price') : 'Compare at Price') + '</th>';
    html += '</tr>';
    html += '</thead>';
    html += '<tbody>';

    // Render each variant (master + non-master)
    variants.forEach(function (variant) {
      var variantId = variant.id;
      var isMaster = variant.is_master || false;
      var optionsText = variant.options_text || variant.display_name || '';
      
      // Display label: Master or options text or SKU
      var displayLabel = isMaster ? (window.Spree && Spree.t ? Spree.t('master', 'Master') : 'Master') : (optionsText || 'Variant');
      
      // Get existing price data
      var existingPrice = priceData[variantId] ? priceData[variantId].price : '';
      var existingComparePrice = priceData[variantId] ? priceData[variantId].compare_price : '';

      html += '<tr data-variant-id="' + variantId + '">';
      html += '<td>';
      html += '<div><strong>' + escapeHtml(displayLabel) + '</strong></div>';
      if (variant.sku) {
        html += '<div><small class="text-muted">SKU: ' + escapeHtml(variant.sku) + '</small></div>';
      }
      html += '</td>';
      
      // Currency column
      html += '<td class="text-center">';
      html += '<span class="text-muted">' + defaultCurrency + '</span>';
      html += '</td>';

      // Price field
      html += '<td>';
      html += '<input type="text" class="form-control form-control-sm" ';
      html += 'data-role="price-field" ';
      html += 'data-variant-id="' + variantId + '" ';
      html += 'data-field="price" ';
      html += 'name="vp[' + variantId + '][' + defaultCurrency + '][price]" ';
      html += 'value="' + escapeHtml(existingPrice) + '" ';
      html += 'placeholder="0.00">';
      html += '</td>';

      // Compare at Price field
      html += '<td>';
      html += '<input type="text" class="form-control form-control-sm" ';
      html += 'data-role="price-field" ';
      html += 'data-variant-id="' + variantId + '" ';
      html += 'data-field="compare_price" ';
      html += 'name="vp[' + variantId + '][' + defaultCurrency + '][compare_price]" ';
      html += 'value="' + escapeHtml(existingComparePrice) + '" ';
      html += 'placeholder="0.00">';
      html += '</td>';

      html += '</tr>';
    });

    html += '</tbody></table></div>';

    container.innerHTML = html;

    // Attach change listeners
    attachPriceFieldListeners();
  }

  // ========== Event Handlers ==========

  function attachPriceFieldListeners() {
    var inputs = document.querySelectorAll('[data-role="price-field"]');
    inputs.forEach(function (input) {
      input.addEventListener('change', handlePriceFieldChange);
    });
  }

  function handlePriceFieldChange(event) {
    var input = event.target;
    var variantId = input.dataset.variantId;
    var field = input.dataset.field;
    var value = input.value;

    if (!priceData[variantId]) {
      priceData[variantId] = {
        price: '',
        compare_price: '',
        currency: defaultCurrency
      };
    }

    priceData[variantId][field] = value;
  }

  function savePriceToRow() {
    if (!currentRowIndex) return;

    var card = document.querySelector('[data-row-index="' + currentRowIndex + '"]');
    if (!card) return;

    var parentCard = card.closest('.update-product-card');
    if (!parentCard) return;

    var productId = parentCard.dataset.productId;

    // Update hidden price data element
    var priceDataEl = document.querySelector('[data-role="price-data"][data-row-index="' + currentRowIndex + '"]');
    if (!priceDataEl) {
      // Create hidden input if it doesn't exist
      priceDataEl = document.createElement('input');
      priceDataEl.type = 'hidden';
      priceDataEl.setAttribute('data-role', 'price-data');
      priceDataEl.setAttribute('data-row-index', currentRowIndex);
      card.appendChild(priceDataEl);
    }

    if (priceDataEl) {
      priceDataEl.value = JSON.stringify(priceData);
    }

    // Create hidden form fields for price updates
    createPriceFormFields(productId);

    // Update summary
    updatePriceSummary();

    closePriceModal();
  }

  function createPriceFormFields(productId) {
    // Remove old price fields
    var oldFields = document.querySelectorAll('input[name^="product_updates[' + productId + '][prices]"]');
    oldFields.forEach(function (field) {
      field.remove();
    });

    // Create new fields
    var form = document.getElementById('product-update-form');
    if (!form) return;

    Object.keys(priceData).forEach(function (variantId) {
      var data = priceData[variantId];
      
      // Price field
      if (data.price !== undefined && data.price !== '') {
        var priceField = document.createElement('input');
        priceField.type = 'hidden';
        priceField.name = 'product_updates[' + productId + '][prices][' + variantId + '][price]';
        priceField.value = data.price;
        form.appendChild(priceField);
      }

      // Compare price field
      if (data.compare_price !== undefined && data.compare_price !== '') {
        var comparePriceField = document.createElement('input');
        comparePriceField.type = 'hidden';
        comparePriceField.name = 'product_updates[' + productId + '][prices][' + variantId + '][compare_price]';
        comparePriceField.value = data.compare_price;
        form.appendChild(comparePriceField);
      }

      // Currency field
      if (data.currency) {
        var currencyField = document.createElement('input');
        currencyField.type = 'hidden';
        currencyField.name = 'product_updates[' + productId + '][prices][' + variantId + '][currency]';
        currencyField.value = data.currency;
        form.appendChild(currencyField);
      }
    });
  }

  function updatePriceSummary() {
    if (!currentRowIndex) return;

    var card = document.querySelector('[data-row-index="' + currentRowIndex + '"]');
    if (!card) return;

    var parentCard = card.closest('.update-product-card');
    if (!parentCard) return;

    var summaryEl = card.querySelector('[data-role="price-summary"]');
    if (!summaryEl) return;

    // Get variants list
    var variantsListEl = document.querySelector('[data-role="price-variants-list"][data-row-index="' + currentRowIndex + '"]');
    if (!variantsListEl) {
      summaryEl.innerHTML = '<p class="text-muted mb-0 small">No variants data found.</p>';
      return;
    }

    var variants = [];
    try {
      variants = JSON.parse(variantsListEl.value || '[]');
    } catch (e) {
      console.error('Error parsing variants list:', e);
      summaryEl.innerHTML = '<p class="text-muted mb-0 small">Error loading variants.</p>';
      return;
    }

    if (variants.length === 0) {
      summaryEl.innerHTML = '<p class="text-muted mb-0 small">No prices configured. Click "Manage Prices" to add.</p>';
      return;
    }

    // Build table HTML (same structure as in the ERB template)
    var html = '<div class="table-responsive">';
    html += '<table class="table table-bordered table-sm mb-0">';
    html += '<colgroup>';
    html += '<col style="width: 30%">';
    html += '<col style="width: 15%">';
    html += '<col style="width: 25%">';
    html += '<col style="width: 30%">';
    html += '</colgroup>';
    html += '<thead class="thead-light">';
    html += '<tr>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('options', 'Options') : 'Options') + '</th>';
    html += '<th class="text-center">' + (window.Spree && Spree.t ? Spree.t('currency', 'Currency') : 'Currency') + '</th>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('price', 'Price') : 'Price') + '</th>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('compare_at_price', 'Compare at Price') : 'Compare at Price') + '</th>';
    html += '</tr>';
    html += '</thead>';
    html += '<tbody>';

    variants.forEach(function (variant) {
      var variantId = variant.id;
      var displayName = variant.display_name || 'Variant';
      var sku = variant.sku || '';
      var variantPriceData = priceData[variantId];

      html += '<tr>';
      
      // Options column
      html += '<td>';
      html += '<div><strong>' + escapeHtml(displayName) + '</strong></div>';
      if (sku) {
        html += '<div><small class="text-muted">SKU: ' + escapeHtml(sku) + '</small></div>';
      }
      html += '</td>';
      
      // Currency column
      html += '<td class="text-center">';
      html += '<span class="text-muted">' + (variantPriceData ? escapeHtml(variantPriceData.currency) : defaultCurrency) + '</span>';
      html += '</td>';
      
      // Price column
      html += '<td>';
      if (variantPriceData && variantPriceData.price) {
        html += escapeHtml(variantPriceData.price);
      } else {
        html += '<span class="text-muted">—</span>';
      }
      html += '</td>';
      
      // Compare at Price column
      html += '<td>';
      if (variantPriceData && variantPriceData.compare_price) {
        html += escapeHtml(variantPriceData.compare_price);
      } else {
        html += '<span class="text-muted">—</span>';
      }
      html += '</td>';
      
      html += '</tr>';
    });

    html += '</tbody>';
    html += '</table>';
    html += '</div>';

    summaryEl.innerHTML = html;
  }

  // ========== Utilities ==========

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // ========== Public API ==========

  function init(currency) {
    if (currency) {
      defaultCurrency = currency;
    }
  }

  function initializeExistingRows() {
    // Initialize price summaries for rows that already have price data
    var priceDataElements = document.querySelectorAll('[data-role="price-data"]');
    priceDataElements.forEach(function (el) {
      var rowIndex = el.getAttribute('data-row-index');
      if (!rowIndex) return;

      try {
        var data = JSON.parse(el.value || '{}');
        if (data && Object.keys(data).length > 0) {
          // Temporarily set state to update summary
          currentRowIndex = rowIndex;
          priceData = data;
          updatePriceSummary();
          currentRowIndex = null;
          priceData = {};
        }
      } catch (e) {
        console.error('Error initializing price summary for row ' + rowIndex + ':', e);
      }
    });
  }

  return {
    init: init,
    openPriceModal: openPriceModal,
    closePriceModal: closePriceModal,
    savePriceToRow: savePriceToRow,
    initializeExistingRows: initializeExistingRows
  };
})();
