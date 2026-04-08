/**
 * File Importer
 * Handles importing product rows from XLSX / CSV files using SheetJS.
 * Expected columns (case-insensitive): Name, SKU, Price
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.FileImporter = (function () {
  'use strict';

  var RowOps = null;

  // ========== Initialization ==========

  function init(rowOperations) {
    RowOps = rowOperations;
  }

  // ========== Column Mapping ==========

  var COLUMN_MAP = {
    name:  ['name', 'product name', 'product_name', 'title'],
    sku:   ['sku', 'product sku', 'product_sku', 'item number', 'item_number'],
    price: ['price', 'master price', 'master_price', 'cost', 'unit price', 'unit_price']
  };

  function findColumnIndex(headers, fieldKey) {
    var aliases = COLUMN_MAP[fieldKey] || [fieldKey];
    for (var i = 0; i < headers.length; i++) {
      var h = (headers[i] || '').toString().trim().toLowerCase();
      if (aliases.indexOf(h) !== -1) return i;
    }
    return -1;
  }

  // ========== File Parsing ==========

  /**
   * Main entry point: reads the file and returns a promise that resolves
   * to { rows: [...], warnings: [...] }.
   */
  function parseFile(file) {
    return new Promise(function (resolve, reject) {
      if (typeof XLSX === 'undefined') {
        reject(new Error('SheetJS (XLSX) library is not loaded.'));
        return;
      }

      var reader = new FileReader();

      reader.onload = function (e) {
        try {
          var data = new Uint8Array(e.target.result);
          var workbook = XLSX.read(data, { type: 'array' });
          var sheetName = workbook.SheetNames[0];
          var worksheet = workbook.Sheets[sheetName];
          var rawRows = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });

          if (!rawRows || rawRows.length < 2) {
            resolve({ rows: [], warnings: ['The file appears to be empty or has no data rows.'] });
            return;
          }

          var headers = rawRows[0].map(function (h) { return (h || '').toString().trim(); });
          var nameIdx  = findColumnIndex(headers, 'name');
          var skuIdx   = findColumnIndex(headers, 'sku');
          var priceIdx = findColumnIndex(headers, 'price');

          var missingCols = [];
          if (nameIdx  === -1) missingCols.push('"Name"');
          if (priceIdx === -1) missingCols.push('"Price"');

          if (missingCols.length > 0) {
            reject(new Error(
              'Required column(s) not found: ' + missingCols.join(', ') + '. ' +
              'Found headers: ' + headers.join(', ')
            ));
            return;
          }

          var rows = [];
          var warnings = [];

          for (var i = 1; i < rawRows.length; i++) {
            var raw = rawRows[i];
            // Skip completely empty rows
            var hasContent = raw.some(function (cell) { return cell !== null && cell !== undefined && cell !== ''; });
            if (!hasContent) continue;

            var name  = skuIdx  >= 0 ? (raw[nameIdx]  || '').toString().trim() : (raw[nameIdx]  || '').toString().trim();
            var sku   = skuIdx  >= 0 ? (raw[skuIdx]   || '').toString().trim() : '';
            var price = priceIdx >= 0 ? (raw[priceIdx] || '').toString().trim() : '';

            name  = (raw[nameIdx]  || '').toString().trim();
            sku   = skuIdx  >= 0 ? (raw[skuIdx]  || '').toString().trim()  : '';
            price = priceIdx >= 0 ? (raw[priceIdx] || '').toString().trim() : '';

            if (!name) {
              warnings.push('Row ' + (i + 1) + ': skipped — "Name" is empty.');
              continue;
            }

            if (!price) {
              warnings.push('Row ' + (i + 1) + ' (' + name + '): "Price" is empty — defaulting to 0.');
              price = '0';
            }

            rows.push({ name: name, sku: sku, price: price });
          }

          resolve({ rows: rows, warnings: warnings });
        } catch (err) {
          reject(new Error('Failed to parse file: ' + err.message));
        }
      };

      reader.onerror = function () {
        reject(new Error('Failed to read file.'));
      };

      reader.readAsArrayBuffer(file);
    });
  }

  // ========== UI Helpers ==========

  function getEl(id) { return document.getElementById(id); }

  function showFeedback(type, html) {
    var el = getEl('xlsx-import-feedback');
    if (!el) return;
    el.innerHTML = '<div class="alert alert-' + type + ' mb-2 py-2">' + html + '</div>';
  }

  function clearFeedback() {
    var el = getEl('xlsx-import-feedback');
    if (el) el.innerHTML = '';
  }

  function showPreview(rows, warnings) {
    var previewSection = getEl('xlsx-import-preview');
    var tbody          = getEl('xlsx-import-preview-tbody');
    var countLabel     = getEl('xlsx-import-count-label');
    var warningBox     = getEl('xlsx-import-warnings');
    var importBtn      = getEl('xlsx-import-confirm-btn');

    if (!previewSection || !tbody) return;

    // Capacity check — use effective (non-empty) row count so the single blank
    // default row that is always present does not steal a slot from the import.
    var maxRows     = RowOps && RowOps.getMaxRows ? RowOps.getMaxRows() : 20;
    var currentCount = RowOps && RowOps.getEffectiveRowCount ? RowOps.getEffectiveRowCount() : (RowOps && RowOps.getRowCount ? RowOps.getRowCount() : 0);
    var available   = maxRows - currentCount;
    var capacityWarning = null;

    if (available <= 0) {
      capacityWarning = '<div class="alert alert-danger py-2 mb-2"><strong>Table is full (' + maxRows + '/' + maxRows + ').</strong> Remove existing rows before importing more.</div>';
    } else if (rows.length > available) {
      capacityWarning = '<div class="alert alert-warning py-2 mb-2"><strong>' + rows.length + ' rows parsed</strong> but only <strong>' + available + '</strong> slot' + (available !== 1 ? 's' : '') + ' available (limit: ' + maxRows + '). Only the first ' + available + ' row' + (available !== 1 ? 's' : '') + ' will be imported.</div>';
    }

    // Warnings
    if (warningBox) {
      var html = '';
      if (capacityWarning) html += capacityWarning;
      if (warnings.length > 0) {
        html += '<div class="alert alert-warning py-2 mb-2">' +
          '<strong>Warnings:</strong><ul class="mb-0 pl-3">' +
          warnings.map(function (w) { return '<li>' + escapeHtml(w) + '</li>'; }).join('') +
          '</ul></div>';
      }
      warningBox.innerHTML = html;
    }

    // Preview table
    tbody.innerHTML = '';
    rows.forEach(function (row, idx) {
      var tr = document.createElement('tr');
      var willBeImported = idx < available;
      
      // Add visual indicator for rows that won't be imported
      if (!willBeImported) {
        tr.classList.add('xlsx-import-row-disabled');
        tr.title = 'This row will not be imported (exceeds limit)';
      }
      
      tr.innerHTML =
        '<td>' + (idx + 1) + '</td>' +
        '<td>' + escapeHtml(row.name)  + '</td>' +
        '<td>' + escapeHtml(row.sku)   + '</td>' +
        '<td>' + escapeHtml(row.price) + '</td>';
      tbody.appendChild(tr);
    });

    var importCount = Math.min(rows.length, Math.max(0, available));

    if (countLabel) {
      countLabel.textContent = rows.length + ' row' + (rows.length !== 1 ? 's' : '') + ' parsed' +
        (rows.length > available && available > 0 ? ' (' + importCount + ' will be imported)' : '');
    }

    if (importBtn) {
      importBtn.textContent = 'Import ' + importCount + ' row' + (importCount !== 1 ? 's' : '');
      importBtn.disabled = importCount === 0;
    }

    previewSection.style.display = rows.length > 0 ? 'block' : 'none';
  }

  function escapeHtml(str) {
    return (str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function clearPreview() {
    var previewSection = getEl('xlsx-import-preview');
    if (previewSection) previewSection.style.display = 'none';
    var tbody = getEl('xlsx-import-preview-tbody');
    if (tbody) tbody.innerHTML = '';
    var warningBox = getEl('xlsx-import-warnings');
    if (warningBox) warningBox.innerHTML = '';
  }

  // ========== Parsed Rows Cache ==========

  var _pendingRows = [];
  var _currentFile  = null;  // kept so the form can carry the original file

  // ========== Event Handlers ==========

  function handleFileChange(event) {
    var file = event.target.files && event.target.files[0];

    // Update Bootstrap 4 custom-file label
    var label = document.querySelector('label[for="xlsx-import-file-input"]');
    if (label) label.textContent = file ? file.name : 'Choose .xlsx or .csv file\u2026';

    _currentFile = file || null;

    if (!file) {
      clearFeedback();
      clearPreview();
      _pendingRows = [];
      // Clear carry inputs
      var carryInput = getEl('xlsx-carry-file-input');
      var nameInput  = getEl('xlsx-import-name-input');
      if (carryInput) carryInput.value = '';
      if (nameInput)  nameInput.value  = '';
      return;
    }

    clearFeedback();
    clearPreview();
    _pendingRows = [];

    var ext = file.name.split('.').pop().toLowerCase();
    if (ext !== 'xlsx' && ext !== 'csv' && ext !== 'xls') {
      showFeedback('danger', 'Unsupported file type <strong>' + escapeHtml(file.name) + '</strong>. Please select a <code>.xlsx</code> or <code>.csv</code> file.');
      return;
    }

    showFeedback('info', '<span class="spinner-border spinner-border-sm mr-1" role="status"></span> Reading file…');

    parseFile(file)
      .then(function (result) {
        _pendingRows = result.rows;
        clearFeedback();

        if (result.rows.length === 0) {
          showFeedback('warning', 'No valid product rows were found in the file.');
          clearPreview();
        } else {
          showFeedback('success',
            '<strong>' + result.rows.length + '</strong> row' + (result.rows.length !== 1 ? 's' : '') + ' parsed successfully from <strong>' + escapeHtml(file.name) + '</strong>. Review below and click <em>Import</em> to add them to the table.'
          );
          showPreview(result.rows, result.warnings);
        }
      })
      .catch(function (err) {
        _pendingRows = [];
        clearPreview();
        showFeedback('danger', '<strong>Error:</strong> ' + escapeHtml(err.message));
      });
  }

  function handleImportConfirm(event) {
    event.preventDefault();
    if (!RowOps || _pendingRows.length === 0) return;

    // Remove any completely empty rows (e.g. the default blank row) before importing
    // so they do not count against the limit.
    if (RowOps.clearEmptyRows) RowOps.clearEmptyRows();

    // Enforce row limit against actual (non-empty) occupied slots
    var maxRows      = RowOps.getMaxRows ? RowOps.getMaxRows() : 20;
    var currentCount = RowOps.getRowCount ? RowOps.getRowCount() : 0;
    var available    = maxRows - currentCount;

    if (available <= 0) {
      showFeedback('danger',
        'The table already has <strong>' + maxRows + '</strong> products (limit reached). ' +
        'Remove some rows first.');
      return;
    }

    var rowsToImport = available < _pendingRows.length
      ? _pendingRows.slice(0, available)
      : _pendingRows;
    var skipped = _pendingRows.length - rowsToImport.length;

    rowsToImport.forEach(function (row) {
      RowOps.addRowWithData(row);
    });

    // Renumber labels sequentially after all rows have been added
    if (RowOps.renumberLabels) RowOps.renumberLabels();

    var count = rowsToImport.length;
    _pendingRows = [];

    // Transfer the original file to the carry input so it is submitted with the form,
    // enabling a ProductImportFile record to be created on the server.
    var carryInput = getEl('xlsx-carry-file-input');
    var nameInput  = getEl('xlsx-import-name-input');
    if (carryInput && _currentFile) {
      try {
        var dt = new DataTransfer();
        dt.items.add(_currentFile);
        carryInput.files = dt.files;
      } catch (e) {
        // DataTransfer not supported in this browser — file record won't be saved
      }
    }
    if (nameInput && _currentFile) {
      nameInput.value = _currentFile.name;
    }
    _currentFile = null;

    // Reset the UI file input (not the carry input)
    var fileInput = getEl('xlsx-import-file-input');
    if (fileInput) fileInput.value = '';
    var label = document.querySelector('label[for="xlsx-import-file-input"]');
    if (label) label.textContent = 'Choose .xlsx or .csv file\u2026';

    clearPreview();
    clearFeedback();

    var feedbackType = skipped > 0 ? 'warning' : 'success';
    var feedbackMsg  = '<strong>' + count + '</strong> product row' + (count !== 1 ? 's' : '') + ' added to the table.';
    if (skipped > 0) {
      feedbackMsg += ' <strong>' + skipped + '</strong> row' + (skipped !== 1 ? 's' : '') +
        ' skipped — import limit of <strong>' + maxRows + '</strong> reached.';
    } else {
      feedbackMsg += ' Review and submit when ready.';
    }
    showFeedback(feedbackType, feedbackMsg);

    // Scroll to table
    var table = document.getElementById('product-import-table');
    if (table) table.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function handleCancelImport(event) {
    event.preventDefault();
    _pendingRows = [];
    _currentFile  = null;
    clearPreview();
    clearFeedback();
    // Clear carry inputs
    var carryInput = getEl('xlsx-carry-file-input');
    var nameInput  = getEl('xlsx-import-name-input');
    if (carryInput) carryInput.value = '';
    if (nameInput)  nameInput.value  = '';
    var fileInput = getEl('xlsx-import-file-input');
    if (fileInput) fileInput.value = '';
    var label = document.querySelector('label[for="xlsx-import-file-input"]');
    if (label) label.textContent = 'Choose .xlsx or .csv file\u2026';
  }

  function handleToggleSection(event) {
    // Don't collapse when clicking the file input or its label
    if (event.target.closest('input, label, button')) return;

    var header = getEl('xlsx-import-section') &&
      document.querySelector('[data-action="toggle-xlsx-import-section"]');
    var body    = getEl('xlsx-import-body');
    var chevron = getEl('xlsx-import-chevron');
    if (!header || !body) return;

    var isExpanded = header.getAttribute('aria-expanded') === 'true';
    if (isExpanded) {
      body.style.display = 'none';
      header.setAttribute('aria-expanded', 'false');
      if (chevron) chevron.style.transform = 'rotate(0deg)';
    } else {
      body.style.display = '';
      header.setAttribute('aria-expanded', 'true');
      if (chevron) chevron.style.transform = 'rotate(90deg)';
    }
  }

  function attachEventListeners() {
    var fileInput  = getEl('xlsx-import-file-input');
    var importBtn  = getEl('xlsx-import-confirm-btn');
    var cancelBtn  = getEl('xlsx-import-cancel-btn');
    var header     = document.querySelector('[data-action="toggle-xlsx-import-section"]');

    if (fileInput) {
      fileInput.addEventListener('change', handleFileChange);
    }
    if (importBtn) {
      importBtn.addEventListener('click', handleImportConfirm);
    }
    if (cancelBtn) {
      cancelBtn.addEventListener('click', handleCancelImport);
    }
    if (header) {
      header.addEventListener('click', handleToggleSection);
    }
  }

  // ========== Public API ==========

  return {
    init: init,
    attachEventListeners: attachEventListeners
  };
})();
