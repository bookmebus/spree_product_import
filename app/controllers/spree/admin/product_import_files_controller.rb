module Spree
  module Admin
    class ProductImportFilesController < ResourceController
      include ProductImportDataLoaders

      # GET /admin/product_import_files/new
      # Renders the product import form
      # Supports two modes:
      # - 'create': Show manual entry form with blank rows
      # - 'update': Show existing products for bulk editing
      def new
        @product_import_file = Spree::ProductImportFile.new
        @mode = params[:mode].presence || 'create'

        if @mode == 'update'
          load_update_products
        else
          @product_import_rows = [default_product_import_row]
        end
      end

      # POST /admin/product_import_files
      # Creates product import(s) from submitted data
      # Routes to either create_single or create_multiple based on params
      def create
        return create_multiple if params[:product_import_files].present?
        return handle_empty_submission unless params[:product_import_file].present?

        create_single
      end

      # POST /admin/product_import_files/bulk_update
      # Updates multiple existing products in a single operation
      # Used from the 'update' mode form
      def bulk_update
        updater = ProductImport::BulkUpdater.new(bulk_update_params, current_ability)
        updater.call

        message = updater.flash_message
        flash[message[:type]] = message[:message]

        redirect_to new_admin_product_import_file_path(
          mode: 'update',
          update_vendor_id: params[:update_vendor_id],
          update_per_page: params[:update_per_page],
          update_page: params[:update_page]
        )
      end

      # GET /admin/product_import_files/vendors.json
      # Lightweight search endpoint for vendor AJAX Select2 (avoids broken /api/v1/vendors ransack)
      def vendors
        return render(json: []) unless defined?(Spree::Vendor)

        scope = Spree::Vendor.accessible_by(current_ability, :index).order(:name)
        if (term = params.dig(:q, :name_cont).presence)
          translation_table = Spree::Vendor.respond_to?(:translation_class) ?
            Spree::Vendor.translation_class.table_name : 'spree_vendor_translations'
          scope = scope.where("#{translation_table}.name ILIKE ?", "%#{term}%")
        end
        render json: scope.limit(50).map { |v| { id: v.id, name: v.name } }
      end

      private

      # ========== Parameter Handling ==========

      # Filters and permits parameters for single file import
      # Returns: Hash with :name and :file keys
      def filter_params
        params.require(:product_import_file).permit(:name, :file)
      end

      # Extracts and permits parameters for bulk product updates
      # Returns: Hash of product updates keyed by product ID
      def bulk_update_params
        return {} unless params[:product_updates].present?

        permitted = {}
        params[:product_updates].each do |product_id, product_data|
          next unless product_data.is_a?(ActionController::Parameters)

          permitted[product_id] = product_data.permit(
            :_selected, :name, :sku, :available_on, :shipping_category_id,
            :master_price, :vendor_id, :detail,
            :meta_title, :meta_keywords, :meta_description,
            taxon_ids: [],
            variants: [
              :sku, :price, :compare_at_price, :cost_price,
              :weight, :height, :width, :depth
            ],
            new_variants: [
              :sku, :price, :compare_at_price, :cost_price,
              :weight, :height, :width, :depth,
              { option_values: {} }
            ],
            images: [:url, :alt]
          ).to_h.deep_symbolize_keys
        end
        permitted
      end

      # Processes and permits parameters for multiple product import rows
      # Handles both manual entry and Excel-imported data
      # Returns: Array of normalized and permitted row parameter hashes
      def product_import_rows_params
        raw_rows = params.fetch(:product_import_files, [])
        
        rows = normalize_rows_array(raw_rows)

        rows.map do |row|
          row_params = row.is_a?(ActionController::Parameters) ? row : ActionController::Parameters.new(row)
          permitted = permit_row_params(row_params)
          
          normalize_nested_params(permitted)
        end
      end

      # Converts various input formats into a consistent array structure
      # Handles Array, Hash, and ActionController::Parameters
      # Returns: Array of row data
      def normalize_rows_array(raw_rows)
        if raw_rows.is_a?(Array)
          raw_rows
        elsif raw_rows.is_a?(ActionController::Parameters) || raw_rows.is_a?(Hash)
          raw_rows.values
        else
          []
        end
      end

      # Permits specific attributes for a single product import row
      # Includes nested attributes for variants, images, and taxons
      # Returns: Hash with symbolized keys
      def permit_row_params(row_params)
        row_params.permit(
          :name, :sku, :prototype_id, :master_price, :available_on,
          :shipping_category_id, :vendor_id, :file, :_selected,
          :detail, :meta_title, :meta_keywords, :meta_description,
          taxon_ids: [],
          option_type_ids: [],
          images: [:attachment, :alt, :url],
          variants: [
            :sku, :price, :compare_at_price, :cost_price,
            :weight, :height, :width, :depth,
            :tax_category_id, :discontinue_on,
            { option_values: {} }
          ]
        ).to_h.deep_symbolize_keys
      end

      # Normalizes nested parameters (variants, images) from hash to array format
      # JavaScript form builders may submit these as hashes with numeric keys
      # Returns: Hash with normalized nested arrays
      def normalize_nested_params(permitted)
        # Convert variants from hash to array if needed
        if permitted[:variants].is_a?(Hash)
          permitted[:variants] = permitted[:variants].values.map do |v|
            v.is_a?(ActionController::Parameters) ? v.to_h.deep_symbolize_keys : v.deep_symbolize_keys
          end
        end

        # Convert images from hash to array if needed
        if permitted[:images].is_a?(Hash)
          permitted[:images] = permitted[:images].values.map do |img|
            img.respond_to?(:deep_symbolize_keys) ? img.deep_symbolize_keys : img
          end
        end
        
        permitted
      end

      # ========== Creation Logic ==========

      # Creates a single file import and enqueues background processing
      # Used when uploading a single CSV/Excel file via the file input
      def create_single
        options = filter_params.merge(user_id: spree_current_user.id, import_type: :file_import)
        creator = ProductImport::Creator.new(options)
        creator.call

        if creator.success?
          flash[:success] = Spree.t('success') + ' Your file import is being processed in the background.'
          redirect_to admin_product_import_files_path
        else
          flash.now[:error] = Spree.t('error')
          @product_import_file = creator.product_import_file
          @product_import_rows = [row_from_options(options)]
          render :new
        end
      end

      # Creates multiple product imports from form data
      # Handles three scenarios:
      # 1. Excel file that was parsed by JavaScript and populated the form
      # 2. Manual entry of multiple products
      # 3. Multiple individual file uploads
      def create_multiple
        rows = filtered_product_import_rows

        if rows.empty?
          handle_empty_rows
          return
        end

        # Check if this is an Excel import that populated the form
        xlsx_file = params[:xlsx_import_file]
        xlsx_name = params[:xlsx_import_name].presence
        
        if xlsx_file.present?
          # This is an Excel import - save the Excel file and process in background
          create_xlsx_import(xlsx_file, xlsx_name)
        else
          # This is either manual entry or direct file uploads
          create_direct_imports(rows)
        end
      end

      # Creates a file import from Excel data parsed by the UI (via SheetJS)
      # The form contains the parsed row data, but we attach the original Excel file for reference
      # Processes all data in the background via BulkCreatorJob
      # 
      # @param xlsx_file [ActionDispatch::Http::UploadedFile] The uploaded Excel file
      # @param xlsx_name [String] Optional custom name for the import
      def create_xlsx_import(xlsx_file, xlsx_name)
        # The UI has already parsed the Excel and populated the form rows
        # This Excel file is just for reference/tracking
        import_name = xlsx_name || xlsx_file.original_filename || "Excel Import - #{Time.current.strftime('%Y-%m-%d %H:%M')}"
        
        # Get the rows that were populated by the UI's JavaScript parser
        rows = filtered_product_import_rows
        
        if rows.empty?
          flash.now[:error] = 'No product data found. Please make sure the Excel file was imported correctly.'
          @product_import_file = Spree::ProductImportFile.new
          @product_import_rows = [default_product_import_row]
          render :new
          return
        end
        
        # Create file import job with the rows data
        # Even though the UI parsed the Excel, we treat it as file_import since the user uploaded a file
        product_import_file = Spree::ProductImportFile.new(
          name: import_name,
          user_id: spree_current_user.id,
          import_type: :file_import,
          status: :active,
          total_rows: rows.size
        )
        
        # Process images and attach to ProductImportFile
        processed_rows = process_images_for_storage(rows, product_import_file)
        product_import_file.row_data = processed_rows.map(&:to_h)
        
        # Attach the original Excel file for reference
        product_import_file.file.attach(xlsx_file)
        
        if product_import_file.save
          ProductImport::BulkCreatorJob.perform_later(product_import_file.id)
          flash[:success] = "Excel file imported successfully! Processing #{rows.size} #{'product'.pluralize(rows.size)} in the background."
          redirect_to admin_product_import_files_path
        else
          flash.now[:error] = 'Failed to create import: ' + product_import_file.errors.full_messages.join(', ')
          @product_import_file = Spree::ProductImportFile.new
          @product_import_rows = rows
          render :new
        end
      end

      # Processes imports that don't have an associated Excel file
      # Separates row data into file uploads (processed synchronously) and
      # manual entries (processed in background)
      # 
      # @param rows [Array<Hash>] Array of product row data
      def create_direct_imports(rows)
        # Separate manual rows from file rows
        manual_rows = rows.reject { |row| row[:file].present? }
        file_rows = rows.select { |row| row[:file].present? }

        # Process file rows synchronously and collect results
        file_results = process_file_rows_sync(file_rows) if file_rows.any?

        # Only create background job for manual rows
        if manual_rows.any?
          create_manual_import_job(manual_rows, file_results)
        elsif file_rows.any?
          # Only file uploads, show results
          handle_file_only_results(file_results)
        else
          # Should not reach here, but handle gracefully
          flash[:error] = "No valid data to import"
          redirect_to admin_product_import_files_path
        end
      end

      # Processes individual file uploads synchronously
      # Each file becomes a separate ProductImportFile record and background job
      # Returns: Hash with :success, :failed counts and :errors array
      # 
      # @param rows [Array<Hash>] Rows containing :file attachments
      # @return [Hash] Processing statistics
      def process_file_rows_sync(rows)
        return { success: 0, failed: 0, errors: [] } if rows.empty?

        success_count = 0
        failed_count = 0
        errors = []

        rows.each_with_index do |row, index|
          # Extract file and name properly
          file = row[:file]
          name = row[:name].presence || file.original_filename
          
          product_import_file = Spree::ProductImportFile.new(
            name: name,
            user_id: spree_current_user.id,
            import_type: :file_import
          )
          
          # Attach the file
          product_import_file.file.attach(file)
          
          if product_import_file.save
            # Enqueue the processor job
            ProductImport::ProcessorJob.perform_later(product_import_file.id)
            success_count += 1
          else
            failed_count += 1
            errors << "File #{index + 1} (#{name}): #{product_import_file.errors.full_messages.join(', ')}"
          end
        end

        { success: success_count, failed: failed_count, errors: errors }
      end

      # Displays flash messages and redirects after processing file-only imports
      # 
      # @param file_results [Hash] Processing statistics from process_file_rows_sync
      def handle_file_only_results(file_results)
        if file_results[:failed] == 0
          flash[:success] = "Successfully uploaded #{file_results[:success]} #{'file'.pluralize(file_results[:success])} for processing."
        else
          flash[:error] = "Failed to upload #{file_results[:failed]} #{'file'.pluralize(file_results[:failed])}: #{file_results[:errors].join('; ')}"
          flash[:success] = "Successfully uploaded #{file_results[:success]} #{'file'.pluralize(file_results[:success])}." if file_results[:success] > 0
        end
        redirect_to admin_product_import_files_path
      end

      # Creates a manual import job for background processing
      # Images are extracted and attached to ProductImportFile, then replaced with references
      # 
      # @param rows [Array<Hash>] Product data from manual entry or parsed Excel
      # @param file_results [Hash, nil] Optional results from file uploads to include in message
      def create_manual_import_job(rows, file_results = nil)
        # Create ProductImportFile record to track the background job
        import_name = params[:import_name].presence || 
                      "Bulk Import - #{Time.current.strftime('%Y-%m-%d %H:%M')}"
        
        product_import_file = Spree::ProductImportFile.new(
          name: import_name,
          user_id: spree_current_user.id,
          import_type: :manual_import,
          status: :active,
          total_rows: rows.size
        )
        
        # Process images and attach to ProductImportFile
        processed_rows = process_images_for_storage(rows, product_import_file)
        product_import_file.row_data = processed_rows.map(&:to_h)

        if product_import_file.save
          # Enqueue background job to process the rows
          ProductImport::BulkCreatorJob.perform_later(product_import_file.id)
          
          # Build success message
          messages = []
          messages << "Processing #{rows.size} manual #{'product'.pluralize(rows.size)} in the background."
          
          if file_results && file_results[:success] > 0
            messages << "Uploaded #{file_results[:success]} #{'file'.pluralize(file_results[:success])} for processing."
          end
          
          flash[:success] = messages.join(' ')
          
          # Add file upload errors if any
          if file_results && file_results[:failed] > 0
            flash[:error] = "File upload errors: #{file_results[:errors].join('; ')}"
          end
          
          redirect_to admin_product_import_files_path
        else
          flash.now[:error] = 'Failed to create import job: ' + product_import_file.errors.full_messages.join(', ')
          @product_import_file = Spree::ProductImportFile.new
          @product_import_rows = rows
          render :new
        end
      end

      # Handles the case when no valid rows are submitted
      # Re-renders the form with an error message
      def handle_empty_rows
        flash.now[:error] = Spree.t('error')
        @product_import_file = Spree::ProductImportFile.new
        @product_import_file.errors.add(:base, 'No products selected or no data provided')
        @product_import_rows = [default_product_import_row]
        render :new
      end

      # Handles the case when no parameters are submitted at all
      # Re-renders the form with an error message
      def handle_empty_submission
        flash.now[:error] = Spree.t('error')
        @product_import_file = Spree::ProductImportFile.new
        @product_import_file.errors.add(:base, 'No data was submitted')
        @product_import_rows = [default_product_import_row]
        render :new
      end

      # ========== Row Filtering ==========

      # Filters submitted rows to only those with data and selected for import
      # Returns: Array of valid, selected rows
      def filtered_product_import_rows
        product_import_rows_params.select { |row| row_has_data?(row) && row_selected?(row) }
      end

      # Checks if a row is marked as selected for import
      # Returns: Boolean
      def row_selected?(row)
        value = row[:_selected].to_s.downcase
        value == '1' || value == 'true' || value == 'on'
      end

      # Checks if a row contains any actual product data
      # Ignores the _selected field when determining if row has data
      # Returns: Boolean
      def row_has_data?(row)
        row.except(:_selected).values.any?(&:present?)
      end

      # ========== Default Data ==========

      # Returns a blank row template for the manual entry form
      # All fields initialized to empty strings with _selected defaulting to '1'
      # Returns: Hash with default product attributes
      def default_product_import_row
        {
          name: '',
          sku: '',
          prototype_id: '',
          master_price: '',
          available_on: '',
          shipping_category_id: '',
          vendor_id: '',
          taxon_ids: [],
          detail: '',
          meta_title: '',
          meta_keywords: '',
          meta_description: '',
          _selected: '1'
        }
      end

      # Converts filter_params options to row format for re-rendering form
      # Used when single file import fails validation
      # Returns: Hash in row format
      def row_from_options(options)
        {
          name: options[:name].to_s,
          sku: options[:sku].to_s,
          prototype_id: options[:prototype_id].to_s,
          master_price: options[:master_price].to_s,
          available_on: options[:available_on].to_s,
          shipping_category_id: options[:shipping_category_id].to_s,
          vendor_id: options[:vendor_id].to_s,
          _selected: options[:_selected].to_s
        }
      end

      # ========== Helper Methods ==========

      # Extracts image files from row data and attaches them to ProductImportFile
      # Replaces uploaded files with attachment keys that can be rehydrated later
      # URL-based images are preserved as-is
      # This allows images to be processed in the background job without losing uploaded files
      # 
      # @param rows [Array<Hash>] Product rows potentially containing image uploads
      # @param product_import_file [ProductImportFile] Record to attach images to
      # @return [Array<Hash>] Modified rows with attachment keys instead of file objects
      def process_images_for_storage(rows, product_import_file)
        image_attachments = []
        
        rows.each_with_index do |row, row_index|
          next unless row[:images].present?
          
          images_array = normalize_images_array(row[:images])
          row[:images] = images_array.map.with_index do |img_data, img_index|
            if img_data[:attachment].present? && img_data[:attachment].respond_to?(:read)
              # This is a file upload - attach it to the ProductImportFile
              attachment_key = "row_#{row_index}_image_#{img_index}"
              
              # Use original filename with a prefix to identify it later
              filename = "#{attachment_key}_#{img_data[:attachment].original_filename}"
              
              image_attachments << {
                file: img_data[:attachment],
                filename: filename,
                alt: img_data[:alt]
              }
              
              # Replace with reference
              {
                attachment_key: attachment_key,
                alt: img_data[:alt]
              }
            elsif img_data[:url].present?
              # URL-based image - can be stored as-is
              {
                url: img_data[:url],
                alt: img_data[:alt]
              }
            else
              # Skip invalid entries
              nil
            end
          end.compact
        end
        
        # Attach all images to the ProductImportFile
        image_attachments.each do |img_info|
          product_import_file.row_images.attach(
            io: img_info[:file],
            filename: img_info[:filename]
          )
        end
        
        rows
      end

      # Normalizes images data from hash or array format to consistent array
      # 
      # @param images_data [Hash, Array, ActionController::Parameters] Images in various formats
      # @return [Array] Normalized array of image data
      def normalize_images_array(images_data)
        if images_data.is_a?(Hash) || images_data.is_a?(ActionController::Parameters)
          images_data.values
        else
          Array(images_data)
        end
      end

      # ========== Collection Override (for index) ==========

      # Overrides ResourceController's collection method to add custom filtering
      # Applies ransack search with default status filter and pagination
      # Returns: ActiveRecord relation of ProductImportFile records
      def collection
        return @collection if @collection.present?

        params[:q] ||= {}
        params[:q][:status] ||= '0'
        params[:q][:s] ||= 'created_at desc'
        
        @collection = super
        
        if params[:q][:deleted_at_null] == '0'
          params.delete(:q)
        end

        @search = Spree::ProductImportFile.ransack(params[:q])
        @collection = @search.result
          .includes(:user, file_attachment: :blob)
          .page(params[:page])
          .per(25)
        
        @collection
      end
    end
  end
end
