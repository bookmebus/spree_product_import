module ProductImport
  class ProductImporter
    MAIN_SHEET = "Main"

    def initialize(xlsx)
      @xlsx = xlsx
      @errors = {}
    end

    def success?
      @errors.blank?
    end

    def call
      @errors = {}
      # {sheet.last_row}, col: #{sheet.last_column}
      # @xlsx.default_sheet = MAIN_SHEET
      @xlsx.default_sheet = 'Main'

      @sheet  = @xlsx.sheet(0)

      if @sheet.last_row <= 1
        return @errors[:product] = I18n.t('product_import.importer.file.no_product_data')
      end

      rows_count = @sheet.last_row

      body_rows_count = rows_count - 1
      body_offset = 2

      body_rows_count.times.each do |index|
        row_index = index + body_offset
        import_row(row_index)
      end
    end

    def import_row(row_index)
      attrs = product_attrs(row_index)
      product = Spree::Product.new(attrs)
      if(!product.save)
        @errors[:row] ||= {}
        @errors[:row][row_index ] = product.errors.full_messages
        return
      end

      update_product_stock(product, row_index)
      update_main_variant_images(product, row_index)
    end

    def update_main_variant_images(product, row_index)

      image_columns.length.times.each do |i|
        column_index = image_columns[i] + 1
        image_path = @sheet.cell(row_index, column_index)
        next if image_path.blank?

        process_product_image(product, image_path)
      end


      # File.new(Spree::Core::Engine.root + 'spec/fixtures' + 'thinking-cat.jpg')

      # image.attachment.attach(io: io), filename: 'thinking-cat.jpg')
    end

    def process_product_image(product, image_path)

      if(image_path.start_with? ('http'))
        io = open(image_path)
      else
        full_path = File.expand_path("../../../../#{image_path}", __FILE__)
        io = open(full_path)
      end

      image = Spree::Image.new
      image.viewable_type = 'Spree::Variant'
      image.viewable_id = product.master.id

      filename = image_path.split("/").last

      image.attachment.attach(io: io, filename: filename)
      image.save
    end

    def update_product_stock(product, row_index)
      stock_amount = @sheet.cell(row_index, 8)
      return if stock_amount.blank?

      stock_loc = stock_location(row_index)
      return if stock_loc.nil?

      stock_item = stock_loc.stock_items.where(variant_id: product.master_id).first_or_create
      stock_item.adjust_count_on_hand(stock_amount.to_i)
    end

    def taxons_for_product(row_index)
      taxons(row_index) || prototype(row_index).taxons
    end

    def taxons(row_index)
      taxon_name = @sheet.cell(row_index, 6)
      return nil if taxon_name.blank?

      taxon_names = taxon_name.split(",").map(&:strip)
      @taxons = Spree::Taxon.where(["name in (?)", taxon_names])
    end

    def product_columns
      # product_column_offset 8
      [
        :name,
        :sku,
        :description,
        :detail, # this column name was used for rich edit with trix editor, however it was not extracted to a gem yet.
        :price,
        :cost_price,
        :promotionable,
        :available_on,
        :discontinue_on,
        :meta_keywords,
        :meta_description,
      ].freeze
    end

    def product_attrs(row_index)
      # Offest of the product is 9
      product_column_offset = 9

      result = { }

      product_columns.each_with_index do |name, index|
        column_index = index + product_column_offset

        cell_value = @sheet.cell(row_index, column_index)
        result[name.to_sym] = cell_value
      end

      # result[:prototype_id] = prototype(row_index).try(:id)
      result[:option_values_hash] = option_values_hash(row_index)
      result[:shipping_category] = shipping_category(row_index)
      result[:tax_category] = tax_category(row_index)
      result[:taxons] = taxons_for_product(row_index)
      result[:vendor] = vendor(row_index)
      result
    end

    # create variants
    # product.option_values_hash = option_values_hash(row_index)
    def option_values_hash(row_index)
      opt_types = option_types(row_index) || prototype(row_index).option_types

      hash = {}
      opt_types.each do |opt_type|
        hash[opt_type.id.to_s] = opt_type.option_value_ids
      end
      hash
    end

    # column number: [index1]
    def image_columns
      return @image_pattern if !@image_pattern.nil?
      @image_columns = []
      (@sheet.last_column).times.each do |i|
        name = @sheet.cell(1, i+1)
        image_pattern = "Image"
        if(name == image_pattern )
          @image_columns << i
        end
      end

      @image_columns
    end

    def property_columns
      return @properties if !@properties.nil?

      @properties = {}

      (@sheet.last_column).times.each do |i|
        name = @sheet.cell(1, i+1)

        property_pattern = "Property "
        if(name.start_with?(property_pattern) )
          property_name = name[property_pattern.length..-1]
          @properties[property_name] = i
        end
      end

      @properties
    end
    
    def stock_location(row_index=2)
      stock_location_name = @sheet.cell(row_index, 7)
      return if stock_location_name.blank?
      Spree::StockLocation.where(name: stock_location_name).first_or_create
    end

    def option_types(row_index=2)
      # return @option_types if !@option_types.nil?
      option_type_values = @sheet.cell(row_index, 6)
      return nil if option_type_values.blank?

      values = option_type_values.split(",").map(&:strip).map(&:downcase).reject(&:blank?)
      @option_types = Spree::OptionType.where(["lower(name) in ( ? )", values ])
    end

    def shipping_category(row_index=2)
      shipping_cat_name = @sheet.cell(row_index, 3)
      return nil if shipping_cat_name.blank?

      @shipping_category ||= Spree::ShippingCategory.find_by name: shipping_cat_name
    end

    def tax_category(row_index=2)
      tax_cat_name = @sheet.cell(row_index, 4)
      return nil if tax_cat_name.blank?

      @tax_category ||= Spree::TaxCategory.find_by name: tax_cat_name
    end

    def prototype(row_index=2)
      prototype_name = @sheet.cell(row_index, 2)
      return nil if prototype_name.blank?

      @prototype ||= Spree::Prototype.find_by name: prototype_name
    end

    def vendor(row_index=2)
      vendor_name = @sheet.cell(row_index, 1)
      return nil if vendor_name.blank?

      @vendor ||= Spree::Vendor.find_by name: vendor_name
    end
  end
end