module ProductImport
  class Creator
    attr_reader :errors
    attr_reader :product_import_file

    def initialize(options)
      @options = options
    end

    def call
      create_product_import_file { enqueue_project_import }
    end

    def create_product_import_file &block
      @errors = nil

      @product_import_file = ::Spree::ProductImportFile.new(@options)

      if @product_import_file.save
        block.call
      else
        @errors = @product_import_file.errors.full_messages
      end
    end

    def enqueue_project_import
      ::ProductImport::ProcessorJob.perform_later(@product_import_file.id)
    end

    def success?
      @errors.nil?
    end

  end
end