/**
 * DOM Helper Functions
 * Utilities for querying and manipulating DOM elements
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.DOMHelpers = (function() {
  'use strict';

  var table = null;

  function setTable(tableElement) {
    table = tableElement;
  }

  function getTable() {
    return table;
  }

  function rowParts(index) {
    if (!table) return { summary: null, details: null };
    
    return {
      summary: table.querySelector('tr.product-import-row[data-row-index="' + index + '"]'),
      details: table.querySelector('tr.product-import-row-details[data-row-index="' + index + '"]')
    };
  }

  function getSelectedCheckboxes() {
    if (!table) return [];
    return Array.prototype.slice.call(table.querySelectorAll('[data-role="row-select"]'));
  }

  function getCheckedCount() {
    return getSelectedCheckboxes().filter(function(input) { 
      return input.checked; 
    }).length;
  }

  function getTemplate() {
    return document.getElementById('product-import-row-template');
  }

  function getModal(modalId) {
    return document.getElementById(modalId);
  }

  function querySelector(selector) {
    if (!table) return null;
    return table.querySelector(selector);
  }

  function querySelectorAll(selector) {
    if (!table) return [];
    return table.querySelectorAll(selector);
  }

  return {
    setTable: setTable,
    getTable: getTable,
    rowParts: rowParts,
    getSelectedCheckboxes: getSelectedCheckboxes,
    getCheckedCount: getCheckedCount,
    getTemplate: getTemplate,
    getModal: getModal,
    querySelector: querySelector,
    querySelectorAll: querySelectorAll
  };
})();
