module ProductImport
  class Importer
    def initialize(product_import_file)
      @product_import_file = product_import_file
    end

    def call
      return if product_import_file.progress?

      # TODO: lock to avoid double process
      @product_import_file.status = :progress
      @product_import_file.save

    end
  end
end