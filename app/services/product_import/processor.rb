module ProductImport
  class Processor

    attr_accessor :errors, :product_import_file

    def initialize(product_import_file)
      @product_import_file = product_import_file
    end

    def call
      return if @product_import_file.in_progress?
      mark_import_in_progress
      reset_errors
      init_handler
      import_products
      import_variants
      mark_import_result
    end

    def reset_errors
      @errors = {}
    end

    def init_handler
      @handler = ProductImport::XlsxHandler.new(@product_import_file)
    end

    def import_products
      @handler.product_data!
      product_importer = ProductImport::ProductImporter.new(@handler)
      import_step_for(product_importer)
    end

    def import_variants
      @handler.variant_data!
      variant_importer = ProductImport::VariantImporter.new(@handler)
      import_step_for(variant_importer)
    end

    def import_step_for(importer)
      importer.call

      if(!importer.success?)
        @errors.merge!(importer.errors)
      end
    end

    def success?
      @errors.blank?
    end

    def mark_import_result
      if(success?)
        mark_import_status(:success)
      else
        mark_import_error(@errors)
      end
    end

    def mark_import_status(status)
      @product_import_file.status = status
      @product_import_file.save
    end

    def mark_import_error(errors)
      @product_import_file.error = errors
      mark_import_status(:failed)
    end


    def mark_import_in_progress
      # TODO: lock to avoid double process
      mark_import_status( :in_progress )
    end
  end
end