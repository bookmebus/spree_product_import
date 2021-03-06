module ProductImport
  class ProcessorJob < ::ApplicationJob
    queue_as :default

    def perform(product_import_file_id)
      product_import_file = ::Spree::ProductImportFile.find(product_import_file_id)
      
      return if product_import_file.nil? || !product_import_file.active?

      ::ProductImport::Processor.new(product_import_file).call
    end
  end
end