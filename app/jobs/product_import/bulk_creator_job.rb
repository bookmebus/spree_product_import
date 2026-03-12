module ProductImport
  # Background job for creating products from row data
  # Handles: manual form entries and Excel files parsed by UI (SheetJS)
  # Processes bulk product creation asynchronously to prevent timeouts
  # and provide better feedback for large batches
  class BulkCreatorJob < ::ApplicationJob
    queue_as :default

    # Main entry point for the background job
    # Processes a ProductImportFile by creating products from its row_data
    # 
    # @param product_import_file_id [Integer] ID of the ProductImportFile to process
    def perform(product_import_file_id)
      product_import_file = ::Spree::ProductImportFile.find(product_import_file_id)
      
      return if product_import_file.nil? || !product_import_file.active?

      process_bulk_creation(product_import_file)
    end

    private

    # Processes bulk product creation from row data
    # Handles the entire lifecycle: prepare rows, create products, update status
    # Distinguishes between failures (product not created) and warnings (product created with issues)
    # 
    # @param product_import_file [ProductImportFile] The import file record to process
    def process_bulk_creation(product_import_file)
      begin
        product_import_file.update_columns(
          status: Spree::ProductImportFile.statuses[:processing],
          updated_at: Time.current
        )
        
        rows = product_import_file.row_data || []
        product_import_file.update_columns(
          total_rows: rows.size,
          updated_at: Time.current
        )

        if rows.empty?
          mark_import_error(product_import_file, { message: 'No product rows to process' })
          return
        end

        # Convert hash keys to symbols for RowCreator
        symbolized_rows = rows.map { |row| symbolize_row(row) }
        
        # Rehydrate images from ProductImportFile attachments
        rehydrate_images(symbolized_rows, product_import_file)
        
        # Process manual rows
        user = product_import_file.user
        creator = ProductImport::RowCreator.new(symbolized_rows, user, product_import_file)
        creator.call
        
        # Update final status
        product_import_file.update_columns(
          processed_rows: rows.size,
          success_count: creator.success_count,
          failure_count: creator.failures.count,
          updated_at: Time.current
        )
        
        # Determine final status based on actual failures, not warnings
        if creator.failures.empty?
          if creator.warnings.any?
            # Success with warnings (product created but images/variants had issues)
            mark_import_success_with_warnings(product_import_file, creator.successes, creator.warnings)
          else
            # Complete success
            mark_import_success(product_import_file, creator.successes)
          end
        else
          # Has actual failures
          error_details = build_error_details(creator.failures, creator.warnings, creator.successes)
          mark_import_error(product_import_file, error_details)
        end

        # row_data is only needed during processing; clear it to free storage
        product_import_file.update_column(:row_data, nil)
        
      rescue StandardError => e
        mark_import_error(product_import_file, {
          message: e.message,
          backtrace: e.backtrace&.first(10)
        })
        # Still clear row_data even on unexpected failure
        product_import_file.update_column(:row_data, nil) rescue nil
        Rails.logger.error("BulkCreatorJob failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
      end
    end

    # Converts row hash with string keys to symbolized keys for service objects
    # Returns: Hash with symbolized keys or original value if not hash-like
    def symbolize_row(row)
      if row.is_a?(Hash)
        row.deep_symbolize_keys
      elsif row.respond_to?(:to_h)
        row.to_h.deep_symbolize_keys
      else
        row
      end
    end

    # Rehydrates image attachments from ProductImportFile back into row data
    # Replaces attachment_key references with actual ActiveStorage blob objects
    # This reverses the process done in controller's process_images_for_storage
    # 
    # @param rows [Array<Hash>] Symbolized product rows
    # @param product_import_file [ProductImportFile] Source of image attachments
    def rehydrate_images(rows, product_import_file)
      # Build a lookup of attachment keys to blobs
      attachments_by_key = {}
      product_import_file.row_images.each do |attachment|
        # Extract key from the filename (format: row_X_image_Y_originalname.ext)
        filename = attachment.filename.to_s
        match = filename.match(/^(row_\d+_image_\d+)_/)
        if match
          key = match[1]
          attachments_by_key[key] = attachment.blob
        end
      end
      
      # Replace attachment_key references with actual blob objects
      rows.each do |row|
        next unless row[:images].present?
        
        row[:images].each do |img_data|
          if img_data[:attachment_key].present?
            blob = attachments_by_key[img_data[:attachment_key]]
            if blob
              # Replace attachment_key with the blob
              img_data.delete(:attachment_key)
              img_data[:blob] = blob
            else
              Rails.logger.warn("Image attachment not found: #{img_data[:attachment_key]}")
            end
          end
        end
      end
    end

    # Builds detailed error structure from failures, warnings, and successes
    # Failures: Product creation failed completely
    # Warnings: Product created but with some issues (e.g., image upload failed)
    # Successes: Products created successfully
    # 
    # @param failures [Array<Hash>] Creation failures with index and errors
    # @param warnings [Array<Hash>] Creation warnings with product_id and errors
    # @param successes [Array<Hash>] Successful creations with product info
    # @return [Hash] Structured error details
    def build_error_details(failures, warnings = [], successes = [])
      details = {}
      
      if failures.any?
        details[:manual_rows] = failures.map do |failure|
          {
            index: failure[:index],
            product_id: failure[:product_id],
            name: failure[:name],
            sku: failure[:sku],
            price: failure[:price],
            is_master: failure[:is_master],
            errors: failure[:errors]
          }
        end
      end
      
      if warnings.any?
        details[:warnings] = warnings.map do |warning|
          {
            product_id: warning[:product_id],
            errors: warning[:errors]
          }
        end
      end

      if successes.any?
        details[:successes] = successes.map do |s|
          {
            product_id: s[:product_id],
            slug: s[:slug],
            name: s[:name],
            sku: s[:sku],
            price: s[:price],
            is_master: s[:is_master]
          }
        end
      end
      
      details
    end

    # Marks import as successful with no issues
    def mark_import_success(product_import_file, successes = [])
      details = successes.any? ? { successes: successes.map { |s| { product_id: s[:product_id], slug: s[:slug], name: s[:name], sku: s[:sku], price: s[:price], is_master: s[:is_master] } } } : nil
      product_import_file.update!(
        status: :success,
        error: details
      )
    end

    # Marks import as successful but with warnings
    # Used when products were created but had minor issues (e.g., some images failed)
    # 
    # @param successes [Array<Hash>] Successfully created products
    # @param warnings [Array<Hash>] Warning details
    def mark_import_success_with_warnings(product_import_file, successes, warnings)
      warning_details = {
        warnings: warnings.map do |warning|
          {
            product_id: warning[:product_id],
            errors: warning[:errors]
          }
        end
      }
      if successes.any?
        warning_details[:successes] = successes.map { |s| { product_id: s[:product_id], slug: s[:slug], name: s[:name], sku: s[:sku], price: s[:price], is_master: s[:is_master] } }
      end
      product_import_file.update!(
        status: :success,
        error: warning_details
      )
    end

    # Marks import as failed
    # 
    # @param error_details [Hash, String] Error information
    def mark_import_error(product_import_file, error_details)
      product_import_file.update_columns(
        status: Spree::ProductImportFile.statuses[:failed],
        error: error_details,
        updated_at: Time.current
      )
    end
  end
end
