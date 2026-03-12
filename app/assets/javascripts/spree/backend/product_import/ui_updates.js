/**
 * UI Update Functions
 * Manages UI state and updates (counts, buttons, checkboxes, etc.)
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.UIUpdates = (function() {
  'use strict';

  var DOM = null;
  var MAX_ROWS = 20;

  function init(domHelpers) {
    DOM = domHelpers;
  }

  function updateSelectAllState() {
    var selectAll = DOM.querySelector('[data-role="select-all"]');
    var selects = DOM.getSelectedCheckboxes();
    var checkedCount = DOM.getCheckedCount();
    
    updateSelectedCount(checkedCount);
    
    if (!selectAll || selects.length === 0) return;

    selectAll.checked = checkedCount === selects.length;
    selectAll.indeterminate = checkedCount > 0 && checkedCount < selects.length;
  }

  function updateSelectedCount(count) {
    var label = DOM.querySelector('[data-role="remove-selected-label"]');
    if (label) {
      label.textContent = 'Remove selected (' + count.toString() + ')';
    }
    
    var button = DOM.querySelector('[data-action="remove-selected"]');
    if (button) {
      button.disabled = count === 0;
    }
  }

  function updateTotalCount() {
    var total = DOM.querySelectorAll('tr.product-import-row[data-row-index]').length;
    var label = DOM.querySelector('[data-role="total-count"]');

    if (label) {
      label.textContent = 'Products: ' + total + ' / ' + MAX_ROWS;
      if (total >= MAX_ROWS) {
        label.style.color = '#dc3545';
        label.style.fontWeight = 'bold';
      } else if (total >= Math.floor(MAX_ROWS * 0.8)) {
        label.style.color = '#fd7e14';
        label.style.fontWeight = 'bold';
      } else {
        label.style.color = '';
        label.style.fontWeight = '';
      }
    }

    updateAddRowButton(total);
  }

  function updateAddRowButton(count) {
    var btn = document.querySelector('[data-action="add-row"]');
    if (!btn) return;
    if (count >= MAX_ROWS) {
      btn.disabled = true;
      btn.title = 'Limit of ' + MAX_ROWS + ' products reached. Remove a row to add more.';
      if (!btn.querySelector('[data-role="add-row-limit-badge"]')) {
        var badge = document.createElement('span');
        badge.setAttribute('data-role', 'add-row-limit-badge');
        badge.textContent = ' (limit reached)';
        badge.style.fontSize = '0.75em';
        btn.appendChild(badge);
      }
    } else {
      btn.disabled = false;
      btn.title = '';
      var badge = btn.querySelector('[data-role="add-row-limit-badge"]');
      if (badge) badge.remove();
    }
  }

  function updateToggleAllButton(state) {
    var button = DOM.querySelector('[data-action="toggle-all"]');
    if (!button) return;

    var label = button.querySelector('[data-role="toggle-all-label"]');
    button.setAttribute('data-state', state);
    
    if (state === 'expanded') {
      button.setAttribute('aria-label', 'Collapse all');
      if (label) label.textContent = 'Collapse all';
    } else {
      button.setAttribute('aria-label', 'Expand all');
      if (label) label.textContent = 'Expand all';
    }
  }

  function setChevronState(button, isExpanded) {
    var icon = button ? button.querySelector('[data-role="row-chevron"]') : null;
    if (!icon) return;
    icon.style.transform = isExpanded ? 'rotate(90deg)' : 'rotate(0deg)';
  }

  return {
    init: init,
    updateSelectAllState: updateSelectAllState,
    updateSelectedCount: updateSelectedCount,
    updateTotalCount: updateTotalCount,
    updateAddRowButton: updateAddRowButton,
    updateToggleAllButton: updateToggleAllButton,
    setChevronState: setChevronState,
    getMaxRows: function() { return MAX_ROWS; }
  };
})();
