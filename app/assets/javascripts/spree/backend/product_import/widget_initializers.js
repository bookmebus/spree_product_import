/**
 * Widget Initializers
 * Handles initialization of third-party widgets (Select2, Flatpickr)
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.WidgetInitializers = (function() {
  'use strict';

  var DOM = null;

  function init(domHelpers) {
    DOM = domHelpers;
  }

  function initRowWidgets(index) {
    initSelect2Widgets(index);
    initFlatpickrWidgets(index);
  }

  function initSelect2Widgets(index) {
    if (!window.jQuery) return;

    var rowSelector = 'tr.product-import-row-details[data-row-index="' + index + '"]';
    var row = document.querySelector(rowSelector);
    if (!row) return;

    // Initialize Select2 for regular selects
    jQuery(row).find('select.select2').each(function() {
      jQuery(this).select2({ 
        width: '100%' 
      });
    });

    // Initialize Select2 for selects with clear button
    jQuery(row).find('select.select2-clear').each(function() {
      jQuery(this).select2({ 
        width: '100%', 
        allowClear: true 
      });
    });
  }

  function initFlatpickrWidgets(index) {
    if (!window.flatpickr) return;

    var rowSelector = 'tr.product-import-row-details[data-row-index="' + index + '"]';
    var row = document.querySelector(rowSelector);
    if (!row) return;

    // flatpickr with wrap:true MUST be called on the wrapper element, not the [data-input] child.
    // _flatpickr is stored on the wrapper so applyBulkValue can find it via wrapper._flatpickr.
    // Always destroy any existing instance (Spree's global `flatpickr('.datepicker', {})` may have
    // run first with wrong options) and reinitialise with our controlled config.
    var wrappers = row.querySelectorAll('.datepicker[data-wrap]');
    wrappers.forEach(function(wrapper) {
      if (wrapper._flatpickr) wrapper._flatpickr.destroy();
      var altFormat = wrapper.getAttribute('data-alt-format') || 'M j, Y';
      flatpickr(wrapper, {
        wrap: true,
        altInput: true,
        altFormat: altFormat,
        dateFormat: 'Y-m-d'
      });
    });
  }

  function initExistingRows() {
    var table = DOM.getTable();
    if (!table) return;

    var rows = table.querySelectorAll('tr.product-import-row[data-row-index]');
    rows.forEach(function(row) {
      var index = row.dataset.rowIndex;
      
      // Update the "Product [index]" label if it's empty
      var indexLabel = row.querySelector('[data-role="row-index-label"]');
      if (indexLabel && !indexLabel.textContent.trim()) {
        indexLabel.textContent = 'Product ' + (parseInt(index, 10) + 1);
      }
      
      initRowWidgets(index);
    });
  }

  return {
    init: init,
    initRowWidgets: initRowWidgets,
    initExistingRows: initExistingRows
  };
})();
