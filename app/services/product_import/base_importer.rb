module ProductImport
  class BaseImporter
    attr_accessor :errors

    def initialize(handler)
      @handler = handler
      @errors = {}
    end

    def call
      @errors = {}
    end

    def success?
      @errors.blank?
    end

    def image_columns
      return @image_columns if @image_columns.present?
      @image_columns = []

      image_header_name = "Image"

      (@handler.cols_count).times.each do |i|
        name = @handler.cell(1, i+1)
        @image_columns << i if (name == image_header_name )
      end
      @image_columns
    end

    def update_product_images(product, row_index)
      update_variant_images(product.master, row_index, :product_variant)
    end

    def update_variant_images(variant, row_index, error_key= :variant)

      image_columns.each do |column_index|
        image_path = @handler.cell(row_index, column_index + 1)

        next if image_path.blank?

        update_variant_image(variant, image_path, error_key, row_index)
      end
    end

    def update_variant_image(variant, image_path, error_key, row_index)
      image_fullpath = image_path.start_with?('http') ? image_path : File.expand_path("../../../../#{image_path}", __FILE__)

      begin 
        io = URI.open(image_fullpath)
      rescue Exception => ex
        error_message(ex.message, error_key, row_index)
        return
      end
      
      image = Spree::Image.new
      image.viewable = variant

      filename = image_path.split("/").last

      image.attachment.attach(io: io, filename: filename)

      error_for(image, error_key, row_index) if !image.save
    end

    def error_message(message, error_key, row_index)
      @errors[error_key] ||= {}
      @errors[error_key][row_index] ||= []
      @errors[error_key][row_index] << message
    end

    def error_for(object, error_key, row_index)
      message = format_error_for(object)
      error_message(message, error_key, row_index)
    end

    def format_error_for(object)
      object.errors.full_messages.join(",")
    end
  end

end