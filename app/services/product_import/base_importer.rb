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
      return @image_columns if !@image_columns.nil?

      @image_columns = []

      image_header_name = "Image"

      (@handler.cols_count).times.each do |i|
        name = @handler.cell(1, i+1)
        @image_columns << i if (name == image_header_name )
      end

      @image_columns
    end

    def update_variant_images(variant, row_index)
      image_columns.each do |column_index|
        image_path = @handler.cell(row_index, column_index + 1)
        next if image_path.blank?
        update_variant_image(variant, image_path)
      end
    end

    def update_variant_image(variant, image_path)

      if(image_path.start_with? ('http'))
        io = URI.open(image_path)
      else
        full_path = File.expand_path("../../../../#{image_path}", __FILE__)
        io = URI.open(full_path)
      end

      image = Spree::Image.new
      image.viewable_type = 'Spree::Variant'
      image.viewable_id = variant

      filename = image_path.split("/").last

      image.attachment.attach(io: io, filename: filename)
      image.save
    end


  end

end