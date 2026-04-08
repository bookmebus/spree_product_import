/**
 * Stock Manager Module
 * Handles stock management modal for update mode:
 *   - Opens modal with product's variants
 *   - Shows stock items for each variant across all stock locations
 *   - Allows editing count_on_hand and backorderable status
 *   - Saves stock data to hidden form fields
 */

// Ensure Spree namespace exists
window.Spree = window.Spree || {};
window.Spree.ProductImport = window.Spree.ProductImport || {};

Spree.ProductImport.StockManager = (function () {
  'use strict';

  // ========== State ==========
  var modal = null;
  var currentRowIndex = null;
  var stockData = {}; // { variant_id: { stock_location_id: { count_on_hand, backorderable } } }
  var stockLocations = []; // Will be populated from server data
  var productName = '';

  // ========== Modal Management ==========

  function openStockModal(rowIndex) {
    currentRowIndex = rowIndex;
    modal = document.getElementById('stock-modal');
    if (!modal) return;

    // Get product info
    var card = document.querySelector('[data-row-index="' + rowIndex + '"]');
    if (!card) return;

    var parentCard = card.closest('.update-product-card');
    if (parentCard) {
      productName = parentCard.querySelector('strong') ? parentCard.querySelector('strong').textContent : 'Product';
    }

    // Update modal title
    var nameEl = document.querySelector('[data-role="stock-modal-product-name"]');
    if (nameEl) {
      nameEl.textContent = productName;
    }

    // Load existing stock data (sets stockLocations from data-stock-locations attribute)
    loadStockData(rowIndex);

    // Show modal immediately so user sees it open
    modal.style.display = 'flex';

    // If no stock locations were found from pre-loaded data, fetch lazily by vendor_id
    if (stockLocations.length === 0) {
      var vendorId = parentCard ? parentCard.getAttribute('data-vendor-id') : null;
      fetchStockLocations(vendorId, function() {
        updateStockLocationBanner();
        renderStockVariants();
      });
    } else {
      updateStockLocationBanner();
      renderStockVariants();
    }
  }

  function fetchStockLocations(vendorId, callback) {
    var container = document.querySelector('[data-role="stock-variants-container"]');
    if (container) {
      container.innerHTML = '<p class="text-muted text-center py-4">Loading stock locations\u2026</p>';
    }
    var url = '/admin/product_import_files/stock_locations';
    if (vendorId) url += '?vendor_id=' + encodeURIComponent(vendorId);
    jQuery.getJSON(url, function(data) {
      stockLocations = Array.isArray(data) ? data : [];
      if (typeof callback === 'function') callback();
    }).fail(function() {
      stockLocations = [];
      if (typeof callback === 'function') callback();
    });
  }

  function updateStockLocationBanner() {
    var locationEl = document.querySelector('[data-role="stock-modal-location-name"]');
    var locationWrapper = document.querySelector('[data-role="stock-location-info-wrapper"]');
    if (locationEl && stockLocations.length > 0) {
      locationEl.textContent = stockLocations[0].name;
      if (locationWrapper) locationWrapper.style.display = 'block';
    } else if (locationWrapper) {
      locationWrapper.style.display = 'none';
    }
  }

  function closeStockModal() {
    if (modal) {
      modal.style.display = 'none';
    }
    currentRowIndex = null;
    stockData = {};
  }

  // ========== Data Loading ==========

  function loadStockData(rowIndex) {
    stockData = {};
    stockLocations = []; // Reset for this product
    
    // Get stock data from hidden input if exists
    var stockDataEl = document.querySelector('[data-role="stock-data"][data-row-index="' + rowIndex + '"]');
    if (stockDataEl) {
      // Load stock items data
      if (stockDataEl.dataset.stock) {
        try {
          var parsed = JSON.parse(stockDataEl.dataset.stock);
          stockData = parsed.stock_items || {};
        } catch (e) {
          console.error('Failed to parse stock data:', e);
        }
      }
      
      // Load stock locations for this product
      if (stockDataEl.dataset.stockLocations) {
        try {
          stockLocations = JSON.parse(stockDataEl.dataset.stockLocations);
        } catch (e) {
          console.error('Failed to parse stock locations:', e);
          stockLocations = [];
        }
      }
    }
  }

  // ========== Rendering ==========

  function renderStockVariants() {
    var container = document.querySelector('[data-role="stock-variants-container"]');
    if (!container) return;

    if (!currentRowIndex) {
      container.innerHTML = '<p class="text-muted text-center py-4">No product selected.</p>';
      return;
    }

    // Get variants data from the row
    var variantsDataEl = document.querySelector('[data-role="variants-data"][data-row-index="' + currentRowIndex + '"]');
    if (!variantsDataEl) {
      container.innerHTML = '<p class="text-muted text-center py-4">No variants data found.</p>';
      return;
    }

    var variantsInfo = { variants: [] };
    try {
      var parsed = JSON.parse(variantsDataEl.dataset.variants || '{}');
      variantsInfo = parsed;
    } catch (e) {
      console.error('Failed to parse variants:', e);
    }

    var variants = variantsInfo.variants || [];

    // Get master variant info from the card
    var card = document.querySelector('[data-row-index="' + currentRowIndex + '"]');
    var parentCard = card ? card.closest('.update-product-card') : null;
    var productId = parentCard ? parentCard.dataset.productId : null;
    var masterVariantId = parentCard ? parentCard.dataset.masterVariantId : null;

    if (variants.length === 0 && masterVariantId) {
      // Only master variant - use master variant ID, not product ID
      var masterSku = parentCard.querySelector('input[name*="[sku]"]');
      var masterName = parentCard.querySelector('strong');
      
      variants.push({
        id: 'master_' + masterVariantId,
        db_id: masterVariantId,
        sku: masterSku ? masterSku.value : '',
        is_master: true,
        display_name: (masterName ? masterName.textContent : 'Master Variant') + ' (Master)'
      });
    }

    // Filter out new variants without database IDs (they can't have stock items yet)
    var existingVariants = variants.filter(function(v) {
      return v.db_id && v.db_id !== '';
    });

    if (existingVariants.length === 0) {
      container.innerHTML = '<div class="alert alert-info">' +
        '<strong>No existing variants found.</strong><br>' +
        'New variants must be saved before stock can be managed. Please save your changes first, then manage stock.' +
        '</div>';
      return;
    }

    if (stockLocations.length === 0) {
      container.innerHTML = '<div class="alert alert-warning">No stock location available for this vendor.</div>';
      return;
    }

    // Show info message if there are new variants that can't be managed yet
    var newVariantsCount = variants.length - existingVariants.length;
    var infoMessageHtml = '';
    if (newVariantsCount > 0) {
      infoMessageHtml = '<div class="alert alert-info mb-3">' +
        '<i class="fa fa-info-circle"></i> ' +
        '<strong>Note:</strong> ' + newVariantsCount + ' new variant' + (newVariantsCount !== 1 ? 's are' : ' is') + ' ' +
        'not shown here. Save your changes first, then you can manage stock for all variants.' +
        '</div>';
    }

    // Simplified layout for single stock location (typical case)
    var html = infoMessageHtml + '<div class="table-responsive"><table class="table table-bordered table-sm">';
    html += '<thead class="thead-light">';
    html += '<tr>';
    html += '<th>Variant</th>';
    html += '<th class="text-center" style="width:150px;">Count on Hand</th>';
    html += '<th class="text-center" style="width:150px;">Backorderable</th>';
    html += '</tr>';
    html += '</thead>';
    html += '<tbody>';

    // Use the first (and typically only) stock location
    var stockLocation = stockLocations[0];

    // Render each existing variant (only those with database IDs)
    existingVariants.forEach(function (variant) {
      html += '<tr>';
      html += '<td><strong>' + escapeHtml(variant.display_name || variant.sku || 'Variant #' + variant.id) + '</strong></td>';
      
      var variantStockData = stockData[variant.db_id] || {};
      var stockItem = variantStockData[stockLocation.id] || { count_on_hand: 0, backorderable: false };
      
      html += '<td class="text-center">';
      html += '<input type="number" ';
      html += 'class="form-control form-control-sm text-center" ';
      html += 'value="' + (stockItem.count_on_hand || 0) + '" ';
      html += 'data-variant-id="' + variant.db_id + '" ';
      html += 'data-stock-location-id="' + stockLocation.id + '" ';
      html += 'data-field="count_on_hand" ';
      html += 'style="width:100px; margin:0 auto;">';
      html += '</td>';
      
      html += '<td class="text-center">';
      html += '<input type="checkbox" ';
      html += (stockItem.backorderable ? 'checked ' : '');
      html += 'data-variant-id="' + variant.db_id + '" ';
      html += 'data-stock-location-id="' + stockLocation.id + '" ';
      html += 'data-field="backorderable" ';
      html += 'style="transform:scale(1.2);">';
      html += '</td>';
      
      html += '</tr>';
    });

    html += '</tbody></table></div>';

    container.innerHTML = html;

    // Attach change listeners
    attachStockFieldListeners();
  }

  // ========== Event Handlers ==========

  function attachStockFieldListeners() {
    var inputs = document.querySelectorAll('[data-role="stock-variants-container"] input');
    inputs.forEach(function (input) {
      input.addEventListener('change', handleStockFieldChange);
    });
  }

  function handleStockFieldChange(event) {
    var input = event.target;
    var variantId = input.dataset.variantId;
    var locationId = input.dataset.stockLocationId;
    var field = input.dataset.field;
    var value = input.type === 'checkbox' ? input.checked : input.value;

    if (!stockData[variantId]) {
      stockData[variantId] = {};
    }
    if (!stockData[variantId][locationId]) {
      stockData[variantId][locationId] = { count_on_hand: 0, backorderable: false };
    }

    stockData[variantId][locationId][field] = value;
  }

  function saveStockToRow() {
    if (!currentRowIndex) return;

    var card = document.querySelector('[data-row-index="' + currentRowIndex + '"]');
    if (!card) return;

    var parentCard = card.closest('.update-product-card');
    if (!parentCard) return;

    var productId = parentCard.dataset.productId;

    // Update hidden stock data element
    var stockDataEl = document.querySelector('[data-role="stock-data"][data-row-index="' + currentRowIndex + '"]');
    if (!stockDataEl) {
      // Create it if it doesn't exist
      var stockSection = document.querySelector('[data-role="stock-content"][data-row-index="' + currentRowIndex + '"]');
      if (stockSection) {
        stockDataEl = document.createElement('div');
        stockDataEl.setAttribute('data-role', 'stock-data');
        stockDataEl.setAttribute('data-row-index', currentRowIndex);
        stockDataEl.style.display = 'none';
        stockSection.appendChild(stockDataEl);
      }
    }

    if (stockDataEl) {
      stockDataEl.dataset.stock = JSON.stringify({ stock_items: stockData });
    }

    // Create hidden form fields for stock updates
    createStockFormFields(productId);

    // Update summary
    updateStockSummary();

    closeStockModal();
  }

  function createStockFormFields(productId) {
    // Remove old stock fields
    var oldFields = document.querySelectorAll('input[name^="product_updates[' + productId + '][stock_items]"]');
    oldFields.forEach(function (field) {
      field.remove();
    });

    // Create new fields
    var form = document.getElementById('product-update-form');
    if (!form) return;

    Object.keys(stockData).forEach(function (variantId) {
      Object.keys(stockData[variantId]).forEach(function (locationId) {
        var item = stockData[variantId][locationId];
        
        // Count on hand
        var countInput = document.createElement('input');
        countInput.type = 'hidden';
        countInput.name = 'product_updates[' + productId + '][stock_items][' + variantId + '][' + locationId + '][count_on_hand]';
        countInput.value = item.count_on_hand || 0;
        form.appendChild(countInput);
        
        // Backorderable
        var backorderableInput = document.createElement('input');
        backorderableInput.type = 'hidden';
        backorderableInput.name = 'product_updates[' + productId + '][stock_items][' + variantId + '][' + locationId + '][backorderable]';
        backorderableInput.value = item.backorderable ? '1' : '0';
        form.appendChild(backorderableInput);
      });
    });
  }

  function updateStockSummary() {
    if (!currentRowIndex) return;

    var summaryEl = document.querySelector('[data-role="stock-summary"][data-row-index="' + currentRowIndex + '"]');
    if (!summaryEl) return;

    // Get variants data to show SKUs
    var variantsDataEl = document.querySelector('[data-role="variants-data"][data-row-index="' + currentRowIndex + '"]');
    var card = document.querySelector('[data-row-index="' + currentRowIndex + '"]');
    var parentCard = card ? card.closest('.update-product-card') : null;
    var masterVariantId = parentCard ? parentCard.dataset.masterVariantId : null;
    
    var variantsInfo = { variants: [] };
    if (variantsDataEl) {
      try {
        var parsed = JSON.parse(variantsDataEl.dataset.variants || '{}');
        variantsInfo = parsed;
      } catch (e) {
        console.error('Failed to parse variants:', e);
      }
    }
    
    var variants = variantsInfo.variants || [];
    
    // If no variants, add master variant
    if (variants.length === 0 && masterVariantId && parentCard) {
      var masterSku = parentCard.querySelector('input[name*="[sku]"]');
      variants.push({
        db_id: masterVariantId,
        sku: masterSku ? masterSku.value : '',
        is_master: true,
        display_name: 'Master'
      });
    }
    
    // Create a map of variant ID to variant info
    var variantMap = {};
    variants.forEach(function(v) {
      variantMap[v.db_id] = v;
    });

    // Check if we have any stock data
    var hasStockData = Object.keys(stockData).length > 0;
    
    if (!hasStockData) {
      summaryEl.innerHTML = '<p class="text-muted mb-0 small">No stock configured. Click "Manage Stock" to add.</p>';
      return;
    }

    // Build table HTML (same structure as ERB template)
    var html = '<div class="table-responsive">';
    html += '<table class="table table-bordered table-sm mb-0">';
    html += '<thead class="thead-light">';
    html += '<tr>';
    html += '<th>' + (window.Spree && Spree.t ? Spree.t('variant', 'Variant') : 'Variant') + '</th>';
    html += '<th class="text-center" style="width:150px;">' + (window.Spree && Spree.t ? Spree.t('count_on_hand', 'Count on Hand') : 'Count on Hand') + '</th>';
    html += '<th class="text-center" style="width:150px;">' + (window.Spree && Spree.t ? Spree.t('backorderable', 'Backorderable') : 'Backorderable') + '</th>';
    html += '</tr>';
    html += '</thead>';
    html += '<tbody>';

    // Add master variant first if it has stock
    if (stockData[masterVariantId]) {
      var masterStockLocations = stockData[masterVariantId];
      var firstLocationId = Object.keys(masterStockLocations)[0];
      var masterStockData = masterStockLocations[firstLocationId];
      
      html += '<tr>';
      html += '<td>';
      html += '<strong>Master</strong>';
      var masterSku = variantMap[masterVariantId] ? variantMap[masterVariantId].sku : '';
      if (masterSku) {
        html += '<div><small class="text-muted">SKU: ' + escapeHtml(masterSku) + '</small></div>';
      }
      html += '</td>';
      html += '<td class="text-center">' + (masterStockData.count_on_hand || 0) + '</td>';
      html += '<td class="text-center">';
      if (masterStockData.backorderable) {
        html += '<span class="badge badge-success">Yes</span>';
      } else {
        html += '<span class="badge badge-secondary">No</span>';
      }
      html += '</td>';
      html += '</tr>';
    }

    // Add non-master variants with stock
    Object.keys(stockData).forEach(function (variantId) {
      // Skip master (already added above)
      if (variantId === masterVariantId) return;
      
      var variantStockLocations = stockData[variantId];
      var firstLocationId = Object.keys(variantStockLocations)[0];
      var variantStockData = variantStockLocations[firstLocationId];
      
      var variant = variantMap[variantId];
      var displayName = variant ? (variant.display_name || variant.sku || 'Variant #' + variantId) : 'Variant #' + variantId;
      var sku = variant ? variant.sku : '';
      
      html += '<tr>';
      html += '<td>';
      html += '<strong>' + escapeHtml(displayName) + '</strong>';
      if (sku) {
        html += '<div><small class="text-muted">SKU: ' + escapeHtml(sku) + '</small></div>';
      }
      html += '</td>';
      html += '<td class="text-center">' + (variantStockData.count_on_hand || 0) + '</td>';
      html += '<td class="text-center">';
      if (variantStockData.backorderable) {
        html += '<span class="badge badge-success">Yes</span>';
      } else {
        html += '<span class="badge badge-secondary">No</span>';
      }
      html += '</td>';
      html += '</tr>';
    });

    html += '</tbody>';
    html += '</table>';
    html += '</div>';

    summaryEl.innerHTML = html;

    // Hide badge since we only show one stock location
    var badge = document.querySelector('[data-role="stock-badge"][data-row-index="' + currentRowIndex + '"]');
    if (badge) {
      badge.style.display = 'none';
    }
  }

  // ========== Utilities ==========

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // ========== Public API ==========

  function init(stockLocationsData) {
    stockLocations = stockLocationsData || [];
    modal = document.getElementById('stock-modal');
  }

  function initializeExistingRows() {
    // Initialize stock summaries for all rows with stock data
    var stockDataElements = document.querySelectorAll('[data-role="stock-data"]');
    stockDataElements.forEach(function (el) {
      var rowIndex = el.dataset.rowIndex;
      if (!rowIndex) return;

      try {
        // Load stock data
        var parsed = JSON.parse(el.dataset.stock || '{}');
        var tempStockData = parsed.stock_items || {};
        
        // Load stock locations for this product
        var tempStockLocations = [];
        if (el.dataset.stockLocations) {
          tempStockLocations = JSON.parse(el.dataset.stockLocations);
        }
        
        // Temporarily set for summary update
        var prevStockData = stockData;
        var prevStockLocations = stockLocations;
        var prevRowIndex = currentRowIndex;
        
        stockData = tempStockData;
        stockLocations = tempStockLocations;
        currentRowIndex = rowIndex;
        
        updateStockSummary();
        
        // Restore previous state
        stockData = prevStockData;
        stockLocations = prevStockLocations;
        currentRowIndex = prevRowIndex;
      } catch (e) {
        console.error('Failed to parse stock data for row ' + rowIndex + ':', e);
      }
    });
    currentRowIndex = null;
    stockData = {};
    stockLocations = [];
  }

  return {
    init: init,
    openStockModal: openStockModal,
    closeStockModal: closeStockModal,
    saveStockToRow: saveStockToRow,
    initializeExistingRows: initializeExistingRows
  };
})();
