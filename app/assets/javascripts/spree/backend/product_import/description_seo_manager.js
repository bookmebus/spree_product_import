(function() {
  'use strict';

  // ========== Description & SEO Manager Module ==========
  // Handles the description and SEO modal, data storage, and summary rendering

  var Spree = window.Spree || {};
  Spree.ProductImport = Spree.ProductImport || {};

  var DescriptionSeoManager = {
    // Dependencies (set by init)
    DOM: null,
    UI: null,
    
    // State
    currentRowIndex: null,
    modal: null,

    // ========== Initialization ==========
    
    init: function(dependencies) {
      this.DOM = dependencies.DOM;
      this.UI = dependencies.UI;
      this.modal = document.getElementById('description-seo-modal');
      
      console.log('DescriptionSeoManager init - modal found:', !!this.modal);
      
      if (!this.modal) {
        console.error('Description/SEO modal not found');
        return;
      }
      
      this.initializeExistingRows();
    },

    initializeExistingRows: function() {
      var table = this.DOM.getTable();
      if (!table) return;
      
      var rows = table.querySelectorAll('.product-import-row-details');
      rows.forEach(function(row) {
        var rowIndex = row.dataset.rowIndex;
        if (rowIndex) {
          this.updateSummary(rowIndex);
        }
      }.bind(this));
    },

    // ========== Modal Operations ==========
    
    openModal: function(rowIndex) {
      console.log('DescSeo.openModal called for row:', rowIndex);
      console.log('Modal element:', this.modal);
      console.log('Modal current display:', this.modal ? this.modal.style.display : 'no modal');
      
      this.currentRowIndex = rowIndex;
      
      // Load existing data into modal
      var descInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-detail-input"]');
      var metaTitleInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-title-input"]');
      var metaKeywordsInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-keywords-input"]');
      var metaDescInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-description-input"]');
      
      // Set values - use Trix API to load HTML into the editor.
      // The stored value is already to_trix_html (inner HTML, no wrapper div).
      var detailHtml = descInput ? descInput.value : '';
      var trixEditor = document.querySelector('trix-editor[input="modal-detail-input"]');
      if (trixEditor && trixEditor.editor) {
        trixEditor.editor.loadHTML(detailHtml);
      } else {
        document.getElementById('modal-detail-input').value = detailHtml;
      }
      document.getElementById('modal-meta-title').value = metaTitleInput ? metaTitleInput.value : '';
      document.getElementById('modal-meta-keywords').value = metaKeywordsInput ? metaKeywordsInput.value : '';
      document.getElementById('modal-meta-description').value = metaDescInput ? metaDescInput.value : '';
      
      console.log('Setting modal display to flex...');
      this.modal.style.display = 'flex';
      console.log('Modal display after setting:', this.modal.style.display);
    },

    closeModal: function() {
      this.modal.style.display = 'none';
      this.currentRowIndex = null;
    },

    saveData: function() {
      if (!this.currentRowIndex) return;
      
      var rowIndex = this.currentRowIndex;
      
      // Get modal values - Trix updates the hidden input automatically
      var detail = document.getElementById('modal-detail-input').value;
      var metaTitle = document.getElementById('modal-meta-title').value;
      var metaKeywords = document.getElementById('modal-meta-keywords').value;
      var metaDescription = document.getElementById('modal-meta-description').value;
      
      // Save to hidden inputs
      var descInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-detail-input"]');
      var metaTitleInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-title-input"]');
      var metaKeywordsInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-keywords-input"]');
      var metaDescInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-description-input"]');
      
      if (descInput) {
        descInput.value = detail;
        // Keep plain-text cache in sync so updateSummary reads clean text after save
        descInput.dataset.plainText = this.stripHtml(detail);
      }
      if (metaTitleInput) metaTitleInput.value = metaTitle;
      if (metaKeywordsInput) metaKeywordsInput.value = metaKeywords;
      if (metaDescInput) metaDescInput.value = metaDescription;
      
      // Update summary display
      this.updateSummary(rowIndex);
      
      this.closeModal();
    },

    // ========== Summary Rendering ==========
    
    updateSummary: function(rowIndex) {
      var summaryContainer = this.DOM.querySelector('[data-role="description-seo-summary"][data-row-index="' + rowIndex + '"]');
      if (!summaryContainer) return;
      
      var descInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-detail-input"]');
      var metaTitleInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-title-input"]');
      var metaKeywordsInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-keywords-input"]');
      var metaDescInput = this.DOM.querySelector('[data-row-index="' + rowIndex + '"] [data-role="row-meta-description-input"]');
      
      // Prefer pre-stripped plain text (set by server or updated after modal save);
      // fall back to truncateHtml for create-mode rows that have no data-plain-text.
      var detailRaw = descInput ? descInput.value : '';
      var detail = descInput
        ? (descInput.dataset.plainText !== undefined && descInput.dataset.plainText !== ''
            ? descInput.dataset.plainText
            : this.stripHtml(detailRaw))
        : '';
      var metaTitle = metaTitleInput ? metaTitleInput.value : '';
      var metaKeywords = metaKeywordsInput ? metaKeywordsInput.value : '';
      var metaDescription = metaDescInput ? metaDescInput.value : '';
      
      var hasData = detailRaw || metaTitle || metaKeywords || metaDescription;
      
      if (!hasData) {
        summaryContainer.innerHTML = '<p class="text-muted mb-0">No detail or SEO information configured</p>';
        return;
      }
      
      var html = '<dl class="row mb-0" style="font-size: 0.9em;">';
      
      if (detail) {
        var truncatedDetail = detail.length > 100 ? this.escapeHtml(detail.substring(0, 100)) + '...' : this.escapeHtml(detail);
        html += '<dt class="col-sm-3">Detail:</dt>';
        html += '<dd class=\"col-sm-9\">' + truncatedDetail + '</dd>';
      }
      
      if (metaTitle) {
        html += '<dt class=\"col-sm-3\">Meta Title:</dt>';
        html += '<dd class=\"col-sm-9\">' + this.escapeHtml(metaTitle) + '</dd>';
      }
      
      if (metaKeywords) {
        html += '<dt class=\"col-sm-3\">Meta Keywords:</dt>';
        html += '<dd class=\"col-sm-9\">' + this.escapeHtml(metaKeywords) + '</dd>';
      }
      
      if (metaDescription) {
        var truncatedDesc = metaDescription.length > 100 ? metaDescription.substring(0, 100) + '...' : metaDescription;
        html += '<dt class=\"col-sm-3\">Meta Description:</dt>';
        html += '<dd class=\"col-sm-9\">' + this.escapeHtml(truncatedDesc) + '</dd>';
      }
      
      html += '</dl>';
      summaryContainer.innerHTML = html;
    },

    // ========== Section Toggle ==========
    
    toggleSection: function(rowIndex) {
      var content = this.DOM.querySelector('[data-role="description-seo-content"][data-row-index="' + rowIndex + '"]');
      var chevron = this.DOM.querySelector('[data-action="toggle-description-seo-section"][data-row-index="' + rowIndex + '"] [data-role="description-seo-chevron"]');
      
      if (!content) return;
      
      var isVisible = content.style.display !== 'none';
      content.style.display = isVisible ? 'none' : 'block';
      
      if (chevron) {
        chevron.style.transform = isVisible ? 'rotate(0deg)' : 'rotate(90deg)';
      }
    },

    // ========== Utilities ==========
    
    escapeHtml: function(text) {
      var div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    },

    stripHtml: function(html) {
      if (!html) return '';
      var temp = document.createElement('div');
      temp.innerHTML = html;
      return (temp.textContent || temp.innerText || '').replace(/\s+/g, ' ').trim();
    },

    truncateHtml: function(html, maxLength) {
      if (!html) return '';
      var text = this.stripHtml(html);
      if (text.length <= maxLength) return this.escapeHtml(text);
      return this.escapeHtml(text.substring(0, maxLength)) + '...';
    }
  };

  // Export to Spree namespace
  Spree.ProductImport.DescriptionSeoManager = DescriptionSeoManager;

})();
