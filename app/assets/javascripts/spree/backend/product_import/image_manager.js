/**
 * Image Manager Module
 * Handles image upload queue, preview, and saving to product rows
 */

Spree.ProductImport = Spree.ProductImport || {};

Spree.ProductImport.ImageManager = (function() {
  'use strict';

  var DOM = null;

  // Stores image data per row: { rowIndex: [{ id, file, alt, previewUrl }, ...] }
  var imagesByRow = {};

  // Per-row form-field base override: { rowIndex: 'product_updates[id][new_images]' }
  // When set, prepareFormSubmission uses this prefix instead of the default.
  var rowFormBases = {};

  // State
  var currentRowIndex = null;
  var modal = null;
  var nextImageId = 1;

  function registerRowFormBase(rowIndex, base) {
    rowFormBases[rowIndex] = base;
  }

  // ========== Initialization ==========

  function init(domHelpers) {
    DOM = domHelpers;
    modal = document.getElementById('images-modal');

    if (!modal) {
      console.error('Images modal not found');
      return;
    }
  }

  // ========== Modal Operations ==========

  function openModal(rowIndex) {
    currentRowIndex = rowIndex;

    // Load images for this row into the modal list
    renderModalImageList();
    updateModalCount();

    modal.style.display = 'flex';

    // Clear the file input and alt text
    var fileInput = document.getElementById('modal-image-file');
    var altInput = document.getElementById('modal-image-alt');
    if (fileInput) fileInput.value = '';
    if (altInput) altInput.value = '';
  }

  function closeModal() {
    modal.style.display = 'none';
    currentRowIndex = null;
  }

  // ========== Add Image to Queue ==========

  function addImageToQueue() {
    var fileInput = document.getElementById('modal-image-file');
    var altInput = document.getElementById('modal-image-alt');

    if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
      alert('Please select an image file first.');
      return;
    }

    var file = fileInput.files[0];
    var alt = altInput ? altInput.value.trim() : '';

    if (!file.type.match(/^image\//)) {
      alert('Please select a valid image file (JPG, PNG, GIF, WebP, etc.).');
      return;
    }

    var imageId = nextImageId++;
    
    var reader = new FileReader();

    reader.onload = function(e) {
      var imageData = {
        id: imageId,
        file: file,
        alt: alt,
        previewUrl: e.target.result,
        name: file.name
      };

      if (!imagesByRow[currentRowIndex]) {
        imagesByRow[currentRowIndex] = [];
      }
      imagesByRow[currentRowIndex].push(imageData);

      renderModalImageList();
      updateModalCount();
    };

    reader.readAsDataURL(file);

    // Clear inputs for next image
    fileInput.value = '';
    if (altInput) altInput.value = '';
  }

  function removeImageFromQueue(imageId) {
    if (!imagesByRow[currentRowIndex]) return;

    imagesByRow[currentRowIndex] = imagesByRow[currentRowIndex].filter(function(img) {
      return img.id !== imageId;
    });

    renderModalImageList();
    updateModalCount();
  }

  // ========== Save to Row ==========

  function saveImagesToRow() {
    if (currentRowIndex === null) {
      console.warn('No current row index');
      return;
    }

    updateRowSummary(currentRowIndex);
    closeModal();
  }

  // ========== Row Summary Rendering ==========

  function updateRowSummary(rowIndex) {
    var summaryContainer = DOM.querySelector(
      '[data-role="images-summary"][data-row-index="' + rowIndex + '"]'
    );
    var countBadge = DOM.querySelector(
      '[data-role="images-count-badge"][data-row-index="' + rowIndex + '"]'
    );

    var images = imagesByRow[rowIndex] || [];

    // Update count badge in card header
    if (countBadge) {
      if (images.length > 0) {
        countBadge.textContent = images.length + ' image' + (images.length !== 1 ? 's' : '');
        countBadge.style.display = '';
      } else {
        countBadge.style.display = 'none';
      }
    }

    if (!summaryContainer) return;

    if (images.length === 0) {
      summaryContainer.innerHTML = '<p class="text-muted mb-0">No images added</p>';
      return;
    }

    var html = '<div class="d-flex flex-wrap" style="gap: 8px;">';
    images.forEach(function(img) {
      html += '<div style="position: relative; width: 72px;" title="' + escapeAttr(img.name) + '">';
      html += '<img src="' + img.previewUrl + '" alt="' + escapeAttr(img.alt || img.name) + '"';
      html += ' style="width: 72px; height: 72px; object-fit: cover; border-radius: 4px; border: 1px solid #dee2e6;" />';
      if (img.alt) {
        html += '<small class="d-block text-truncate text-muted" style="font-size: 10px; max-width: 72px;">' + escapeHtml(img.alt) + '</small>';
      }
      html += '</div>';
    });
    html += '</div>';

    summaryContainer.innerHTML = html;
  }

  // ========== Modal List Rendering ==========

  function renderModalImageList() {
    var listContainer = document.getElementById('modal-images-list');
    var noImagesMsg = document.getElementById('modal-no-images');

    if (!listContainer) return;

    var images = imagesByRow[currentRowIndex] || [];

    if (images.length === 0) {
      listContainer.innerHTML = '';
      if (noImagesMsg) noImagesMsg.style.display = '';
      return;
    }

    if (noImagesMsg) noImagesMsg.style.display = 'none';

    var html = '<table class="table table-sm mb-0">';
    html += '<thead><tr>';
    html += '<th style="width: 80px;">Preview</th>';
    html += '<th>Filename</th>';
    html += '<th>Alt Text</th>';
    html += '<th class="text-right" style="width: 80px;">Actions</th>';
    html += '</tr></thead>';
    html += '<tbody>';

    images.forEach(function(img) {
      html += '<tr>';
      html += '<td><img src="' + img.previewUrl + '" alt="' + escapeAttr(img.alt || img.name) + '"';
      html += ' style="width: 60px; height: 60px; object-fit: cover; border-radius: 4px; border: 1px solid #dee2e6;" /></td>';
      html += '<td class="align-middle"><small class="text-truncate d-block" style="max-width: 200px;" title="' + escapeAttr(img.name) + '">' + escapeHtml(img.name) + '</small></td>';
      html += '<td class="align-middle">';
      html += '<input type="text" class="form-control form-control-sm modal-image-alt-edit" data-image-id="' + img.id + '" value="' + escapeAttr(img.alt) + '" placeholder="Alt text..." />';
      html += '</td>';
      html += '<td class="align-middle text-right">';
      html += '<button type="button" class="btn btn-danger btn-sm" data-action="remove-modal-image" data-image-id="' + img.id + '">';
      html += '<span class="icon icon-trash"></span>';
      html += '</button>';
      html += '</td>';
      html += '</tr>';
    });

    html += '</tbody></table>';
    listContainer.innerHTML = html;

    // Attach alt text change listeners
    listContainer.querySelectorAll('.modal-image-alt-edit').forEach(function(input) {
      input.addEventListener('input', function() {
        updateImageAlt(parseInt(this.getAttribute('data-image-id'), 10), this.value);
      });
    });
  }

  function updateImageAlt(imageId, altText) {
    var images = imagesByRow[currentRowIndex] || [];
    var img = images.find(function(i) { return i.id === imageId; });
    if (img) img.alt = altText;
  }

  function updateModalCount() {
    var countEl = document.getElementById('modal-images-count');
    if (!countEl) return;

    var images = imagesByRow[currentRowIndex] || [];
    countEl.textContent = images.length > 0
      ? images.length + ' image' + (images.length !== 1 ? 's' : '') + ' in queue'
      : 'No images in queue';
  }

  // ========== Section Toggle ==========

  function toggleSection(rowIndex) {
    var content = DOM.querySelector(
      '[data-role="images-content"][data-row-index="' + rowIndex + '"]'
    );
    var chevron = DOM.querySelector(
      '[data-action="toggle-images-section"][data-row-index="' + rowIndex + '"] [data-role="images-chevron"]'
    );

    if (!content) return;

    var isVisible = content.style.display !== 'none';
    content.style.display = isVisible ? 'none' : 'block';

    if (chevron) {
      chevron.style.transform = isVisible ? 'rotate(0deg)' : 'rotate(90deg)';
    }
  }

  // ========== Form Submission Hook ==========
  // Call this before form submit to inject hidden file inputs per row

  function prepareFormSubmission(form) {
    Object.keys(imagesByRow).forEach(function(rowIndex) {
      var images = imagesByRow[rowIndex];
      
      if (!images || images.length === 0) return;

      images.forEach(function(imgData, idx) {
        var fieldBase = rowFormBases[rowIndex]
          ? (rowFormBases[rowIndex] + '[' + idx + ']')
          : ('product_import_files[' + rowIndex + '][images][' + idx + ']');

        // Create file input using DataTransfer
        if (typeof DataTransfer !== 'undefined') {
          try {
            var dt = new DataTransfer();
            dt.items.add(imgData.file);

            var fileInput = document.createElement('input');
            fileInput.type = 'file';
            fileInput.name = fieldBase + '[attachment]';
            fileInput.style.display = 'none';
            fileInput.files = dt.files;
            form.appendChild(fileInput);
          } catch (e) {
            console.warn('DataTransfer not supported for image', imgData.name, e);
          }
        } else {
          console.warn('DataTransfer not available');
        }

        // Alt text hidden input
        var altInput = document.createElement('input');
        altInput.type = 'hidden';
        altInput.name = fieldBase + '[alt]';
        altInput.value = imgData.alt || '';
        form.appendChild(altInput);
      });
    });
  }

  // ========== Utilities ==========

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  }

  function escapeAttr(text) {
    return (text || '').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function getImageCount(rowIndex) {
    return (imagesByRow[rowIndex] || []).length;
  }

  function getImagesByRow() {
    return imagesByRow;
  }

  function getRowFormBases() {
    return rowFormBases;
  }

  // ========== Public API ==========

  return {
    init: init,
    openModal: openModal,
    closeModal: closeModal,
    addImageToQueue: addImageToQueue,
    removeImageFromQueue: removeImageFromQueue,
    saveImagesToRow: saveImagesToRow,
    updateRowSummary: updateRowSummary,
    toggleSection: toggleSection,
    prepareFormSubmission: prepareFormSubmission,
    getImageCount: getImageCount,
    getImagesByRow: getImagesByRow,
    getRowFormBases: getRowFormBases,
    registerRowFormBase: registerRowFormBase
  };
})();
