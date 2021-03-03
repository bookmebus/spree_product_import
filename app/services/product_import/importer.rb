module ProductImport
  class Importer

    attr_accessor :errors

    def initialize(product_import_file)
      @product_import_file = product_import_file
    end

    def call
      return if @product_import_file.in_progress?

      @handler = ProductImport::XlsxHandler.new(@product_import_file)
      mark_import_in_progress

      product_importer = ProductImport::ProductImporter.new(@handler.product_data!)
      product_importer.call

      variant_importer = ProductImport::VariantImporter.new(@handler.variant_data!)
      variant_importer.call
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