module Spree
  class ProductImportFile < Spree::Base
    serialize :error, Hash
    serialize :row_data, JSON
  
    ALLOW_FORMATS = %w(text/csv application/vnd.openxmlformats-officedocument.spreadsheetml.sheet).freeze
   
    belongs_to :user, class_name: "#{Spree.user_class}"
    has_one_attached :file
    has_many_attached :row_images

    enum status: %i[active processing success failed canceled]
    enum import_type: %i[file_import manual_import]

    validates :name, presence: true
    validates :file, attached: true, content_type: ALLOW_FORMATS, if: -> { file_import? }
    
    # Manual imports can optionally have a file (e.g., original Excel for reference)
    # but must have row_data for processing
    validate :validate_manual_import_data, if: -> { manual_import? }

    self.default_ransackable_attributes = %w[id name file_name updated_at created_at]

    before_save :set_file_name

    # Sets the file_name attribute from the attached file
    # Called before save to keep file_name in sync with actual attachment
    def set_file_name
      self.file_name = file.blob.filename if file.attached?
    end

    # Calculates progress percentage based on rows processed vs total
    # Returns: Float percentage (0-100) with 2 decimal places
    def progress_percentage
      return 0 if total_rows.zero?
      ((processed_rows.to_f / total_rows) * 100).round(2)
    end

    # Returns a summary hash of the import status
    # Useful for API responses or status displays
    # Returns: Hash with status, counts, and percentage
    def status_summary
      {
        status: status,
        total: total_rows,
        processed: processed_rows,
        success: success_count,
        failed: failure_count,
        percentage: progress_percentage
      }
    end

    private

    # Validates that manual imports have row_data
    # Manual imports don't require a file attachment but must have data to process
    def validate_manual_import_data
      if row_data.blank? || (row_data.is_a?(Array) && row_data.empty?)
        errors.add(:row_data, "must be present for manual imports")
      end
    end
    
  end
end
