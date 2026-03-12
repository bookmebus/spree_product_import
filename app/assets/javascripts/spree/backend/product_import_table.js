/**
 * Product Import Table - Main Orchestrator
 * Coordinates all modules for product import functionality
 */

// Ensure Spree namespace exists
window.Spree = window.Spree || {};
window.Spree.ProductImport = window.Spree.ProductImport || {};

Spree.ProductImportTable = (function() {
  'use strict';

  // ========== Initialization ==========

  function setOptionTypesData(data) {
    if (Spree.ProductImport.VariantManager) {
      Spree.ProductImport.VariantManager.setOptionTypesData(data);
    }
  }

  function init(optionTypes) {
    var table = document.getElementById('product-import-table');
    if (!table) {
      console.warn('Product import table not found');
      return;
    }

    // Get module references (must be done inside init, after modules are loaded)
    var DOM = Spree.ProductImport.DOMHelpers;
    var UI = Spree.ProductImport.UIUpdates;
    var RowOps = Spree.ProductImport.RowOperations;
    var Variants = Spree.ProductImport.VariantManager;
    var DescSeo = Spree.ProductImport.DescriptionSeoManager;
    var Widgets = Spree.ProductImport.WidgetInitializers;
    var Events = Spree.ProductImport.EventHandlers;
    var ImgMgr = Spree.ProductImport.ImageManager;
    var FileImporter = Spree.ProductImport.FileImporter;

    // Check if all modules are loaded
    if (!DOM || !UI || !RowOps || !Variants || !DescSeo || !Widgets || !Events) {
      console.error('Product Import modules not loaded properly', {
        DOM: !!DOM,
        UI: !!UI,
        RowOps: !!RowOps,
        Variants: !!Variants,
        DescSeo: !!DescSeo,
        Widgets: !!Widgets,
        Events: !!Events
      });
      return;
    }

    var nextIndex = parseInt(table.getAttribute('data-next-index'), 10) || 0;

    // Initialize all modules
    DOM.setTable(table);
    UI.init(DOM);
    Widgets.init(DOM);
    RowOps.init(DOM, UI, Widgets);
    Variants.init(DOM);
    DescSeo.init({ DOM: DOM, UI: UI });
    if (ImgMgr) ImgMgr.init(DOM);
    if (FileImporter) FileImporter.init(RowOps);
    Events.init(DOM, UI, RowOps, Variants, DescSeo, ImgMgr || null);

    // Set next row index
    RowOps.setNextIndex(nextIndex);

    // Set option types data
    if (optionTypes) {
      setOptionTypesData(optionTypes);
    } else if (window.spreeProductImportOptionTypes) {
      setOptionTypesData(window.spreeProductImportOptionTypes);
    }

    // Initialize existing rows
    Widgets.initExistingRows();

    // Restore state from server-rendered data (after validation errors)
    if (Variants) Variants.initializeExistingRows();
    if (DescSeo && DescSeo.initializeExistingRows) DescSeo.initializeExistingRows();

    // Attach event listeners
    Events.attachEventListeners();
    if (FileImporter) FileImporter.attachEventListeners();

    // Hook form submit to inject image file inputs
    var form = document.querySelector('form[action*="product_import_files"]');
    if (form && ImgMgr) {
      form.addEventListener('submit', function() {
        ImgMgr.prepareFormSubmission(form);
      });
    }

    // Update initial UI state
    UI.updateSelectAllState();
    UI.updateTotalCount();
    UI.updateToggleAllButton('expanded');

    console.log('Product Import Table initialized successfully');
  }

  // ========== Public API ==========

  return {
    init: init,
    setOptionTypesData: setOptionTypesData
  };
})();

// Auto-initialize on page load
(function() {
  function initializeProductImportTable() {
    Spree.ProductImportTable.init();
  }

  document.addEventListener('DOMContentLoaded', initializeProductImportTable);
  document.addEventListener('turbolinks:load', initializeProductImportTable);
})();
