require 'roo'

module ProductImport
  class Importer

    attr_accessor :errors

    def initialize(product_import_file)
      @product_import_file = product_import_file
    end

    def call
      return if @product_import_file.in_progress?

      mark_import_in_progress

      # path = Rails.application.routes.url_helpers.rails_blob_path(@product_import_file.file, only_path: true)
      @product_import_file.file.open do |file|
        process_file(file)
      end
    end

    def process_file(file)
      @xlsx ||= Roo::Spreadsheet.open(file)
      
      product_importer = ProductImport::ProductImporter.new(@xlsx)
      product_importer.call

      variant_importer = ProductImport::VariantImporter.new(@xlsx)
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