/**
 * Row Operations
 * Manages adding, removing, expanding/collapsing product rows
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.RowOperations = (function() {
  'use strict';

  var DOM = null;
  var UI = null;
  var Widgets = null;
  var nextIndex = 0;
  var MAX_ROWS = 20;

  function getRowCount() {
    var table = DOM.getTable();
    if (!table || !table.tBodies[0]) return 0;
    return table.tBodies[0].querySelectorAll('tr.product-import-row').length;
  }

  /**
   * Count only rows that have a non-empty name field.
   * Used by the file importer so a single blank default row does not
   * count against the import limit.
   */
  function getEffectiveRowCount() {
    var table = DOM.getTable();
    if (!table || !table.tBodies[0]) return 0;
    var rows = table.tBodies[0].querySelectorAll('tr.product-import-row[data-row-index]');
    var count = 0;
    rows.forEach(function(row) {
      var index = row.dataset.rowIndex;
      var nameInput = DOM.querySelector(
        'input[data-role="row-name-input"][id*="_' + index + '_"]'
      );
      if (nameInput && nameInput.value.trim() !== '') count++;
    });
    return count;
  }

  function init(domHelpers, uiUpdates, widgetInitializers) {
    DOM = domHelpers;
    UI = uiUpdates;
    Widgets = widgetInitializers;
  }

  function setNextIndex(index) {
    nextIndex = index;
  }

  function getNextIndex() {
    return nextIndex;
  }

  function toggleDetails(index, toggleButton) {
    var parts = DOM.rowParts(index);
    if (!parts.details) return;

    var isCollapsed = parts.details.style.display === 'none';
    parts.details.style.display = isCollapsed ? '' : 'none';
    toggleButton.setAttribute('aria-expanded', isCollapsed ? 'true' : 'false');
    UI.setChevronState(toggleButton, isCollapsed);
  }

  function removeRow(indexOrRow) {
    var index = null;
    if (typeof indexOrRow === 'string' || typeof indexOrRow === 'number') {
      index = indexOrRow;
    } else if (indexOrRow && indexOrRow.dataset) {
      index = indexOrRow.dataset.rowIndex;
    }

    if (index === null) return;

    var parts = DOM.rowParts(index);
    if (parts.details) parts.details.remove();
    if (parts.summary) parts.summary.remove();
    UI.updateTotalCount();
    UI.updateSelectAllState();
  }

  function addRow() {
    if (getRowCount() >= MAX_ROWS) {
      UI.updateAddRowButton(MAX_ROWS); // ensure button state is correct
      return false;
    }

    var template = DOM.getTemplate();
    if (!template) return false;

    var markup = template.innerHTML.replace(/__INDEX__/g, nextIndex);
    var container = document.createElement('tbody');
    container.innerHTML = markup;

    var table = DOM.getTable();
    while (container.firstChild) {
      table.tBodies[0].appendChild(container.firstChild);
    }

    var newSummary = DOM.querySelector('tr.product-import-row[data-row-index="' + nextIndex + '"]');
    if (newSummary) {
      // Update the "Product [index]" label using the actual row count, not nextIndex,
      // so that labels stay sequential even when rows have been removed before this add.
      var indexLabel = newSummary.querySelector('[data-role="row-index-label"]');
      if (indexLabel) {
        var rowCount = table.tBodies[0].querySelectorAll('tr.product-import-row').length;
        indexLabel.textContent = 'Product ' + rowCount;
      }

      // Pre-select the checkbox
      var checkbox = newSummary.nextElementSibling ? 
        newSummary.querySelector('[data-role="row-select"]') : null;
      if (!checkbox) {
        // Try finding in the details row
        var parts = DOM.rowParts(nextIndex);
        if (parts.summary) {
          checkbox = parts.summary.querySelector('[data-role="row-select"]');
        }
      }
      if (checkbox) {
        checkbox.checked = true;
      }

      newSummary.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      
      var nameInput = DOM.querySelector('input[data-role="row-name-input"][id*="_' + nextIndex + '_"]');
      if (nameInput) {
        setTimeout(function() { nameInput.focus(); }, 300);
      }
    }

    Widgets.initRowWidgets(nextIndex);
    UI.updateSelectAllState();
    UI.updateTotalCount();
    nextIndex += 1;
    table.setAttribute('data-next-index', nextIndex);
    return true;
  }

  function expandAll() {
    DOM.querySelectorAll('tr.product-import-row[data-row-index]').forEach(function(row) {
      var index = row.dataset.rowIndex;
      var toggleBtn = row.querySelector('[data-action="toggle-row"]');
      var details = DOM.rowParts(index).details;
      
      if (details && details.style.display === 'none') {
        details.style.display = '';
        toggleBtn.setAttribute('aria-expanded', 'true');
        UI.setChevronState(toggleBtn, true);
      }
    });
  }

  function collapseAll() {
    DOM.querySelectorAll('tr.product-import-row[data-row-index]').forEach(function(row) {
      var index = row.dataset.rowIndex;
      var toggleBtn = row.querySelector('[data-action="toggle-row"]');
      var details = DOM.rowParts(index).details;
      
      if (details && details.style.display !== 'none') {
        details.style.display = 'none';
        toggleBtn.setAttribute('aria-expanded', 'false');
        UI.setChevronState(toggleBtn, false);
      }
    });
  }

  function removeSelectedRows() {
    var table = DOM.getTable();
    var selects = table.querySelectorAll('[data-role="row-select"]:checked');
    selects.forEach(function(checkbox) {
      var row = checkbox.closest('tr[data-row-index]');
      if (row) removeRow(row);
    });
    UI.updateSelectAllState();
  }

  /**
   * Remove any rows whose name field is blank (e.g. the default empty row).
   */
  function clearEmptyRows() {
    var allRows = DOM.querySelectorAll('tr.product-import-row[data-row-index]');
    allRows.forEach(function(row) {
      var index = row.dataset.rowIndex;
      var nameInput = DOM.querySelector(
        'input[data-role="row-name-input"][id*="_' + index + '_"]'
      );
      if (!nameInput || nameInput.value.trim() === '') {
        removeRow(index);
      }
    });
  }

  /**
   * Renumber all visible row labels sequentially: Product 1, Product 2 …
   */
  function renumberLabels() {
    var allRows = DOM.querySelectorAll('tr.product-import-row[data-row-index]');
    allRows.forEach(function(row, i) {
      var label = row.querySelector('[data-role="row-index-label"]');
      if (label) label.textContent = 'Product ' + (i + 1);
    });
  }

  /**
   * Add a new row pre-populated with data from an imported file.
   * @param {Object} data - { name, sku, price }
   */
  function addRowWithData(data) {
    var rowIndex = nextIndex; // capture before addRow() increments it
    if (!addRow()) return false; // limit reached

    // Populate name
    if (data.name) {
      var nameInput = DOM.querySelector(
        'input[data-role="row-name-input"][id*="_' + rowIndex + '_"]'
      );
      if (nameInput) nameInput.value = data.name;
    }

    // Populate SKU
    if (data.sku) {
      var skuInput = DOM.querySelector(
        'input[data-role="row-sku-input"][id*="_' + rowIndex + '_"]'
      );
      if (skuInput) skuInput.value = data.sku;
    }

    // Populate price
    if (data.price !== undefined && data.price !== '') {
      var priceInput = DOM.querySelector(
        'input[data-role="row-price-input"][id*="_' + rowIndex + '_"]'
      );
      if (priceInput) priceInput.value = data.price;
    }

    return true;
  }

  return {
    init: init,
    setNextIndex: setNextIndex,
    getNextIndex: getNextIndex,
    getRowCount: getRowCount,
    getEffectiveRowCount: getEffectiveRowCount,
    getMaxRows: function() { return MAX_ROWS; },
    toggleDetails: toggleDetails,
    removeRow: removeRow,
    addRow: addRow,
    addRowWithData: addRowWithData,
    clearEmptyRows: clearEmptyRows,
    renumberLabels: renumberLabels,
    expandAll: expandAll,
    collapseAll: collapseAll,
    removeSelectedRows: removeSelectedRows
  };
})();
