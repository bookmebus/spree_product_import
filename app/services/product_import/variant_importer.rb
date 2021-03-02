module ProductImport
  class VariantImporter    
    def initialize(xlsx)
      @xlsx = xlsx
      @errors = {}
    end

    def call
      @errors = {}
      # {sheet.last_row}, col: #{sheet.last_colum

      @xlsx.default_sheet = 'Variant'
      @sheet = @xlsx.sheet(1)

      if @sheet.last_row <= 1
        return @errors[:variant] = I18n.t('product_import.importer.file.no_variant_data')
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
      master_sku = @sheet.cell(row_index, 1)
      master_variant = Spree::Variant.where(is_master: true).find_by(sku: master_sku)

      if(master_variant.nil?)
        @errors[:variant] ||= {}
        @errors[:variant][row_index.to_s] = "sku: #{master_sku} no found" 
        return
      end

      sku = @sheet.cell(row_index, 2)
      position = @sheet.cell(row_index, 3)
      weight = @sheet.cell(row_index, 4)
      width = @sheet.cell(row_index, 5)
      height = @sheet.cell(row_index, 6)
      depth = @sheet.cell(row_index, 7)
      discontinue_on = @sheet.cell(row_index, 8)
      cost_value = @sheet.cell(row_index, 9)
      cost = Monetize.parse(cost_value)

      product = master_variant.product

      options = {
        sku: sku,
        position: position,
        weight: weight,
        width: width,
        height: height,
        depth: depth,
        discontinue_on: discontinue_on,
        cost_price: cost&.amount,
        cost_currency: cost&.currency&.to_s,
        product_id: product.id,
        tax_category_id: product.tax_category_id,
        vendor_id: product.vendor_id,
        is_master: false,
        track_inventory: true,
      }

      matched_variant = nil
      product.variants.includes(option_values: :option_type).each do |variant|
        if variant_matched?(row_index, variant)
          matched_variant = variant
          break
        end
      end

      result = matched_variant.update(options)
      if !result
        error_message = matched_variant.errors.full_messages.join("\n")
        @errors[:variant][row_index.to_s] = "can not update variant: #{row_index} #{master_sku} with error: #{error_message}"
        return
      end

      update_variant_stock(matched_variant, row_index)
      update_variant_price(matched_variant, row_index)
      update_variant_image(matched_variant, row_index)
    end

    def update_variant_image(variant, row_index)
      image_columns.length.times.each do |i|
        column_index = image_columns[i] + 1
        image_path = @sheet.cell(row_index, column_index)
        next if image_path.blank?
        process_variant_image(variant, image_path)
      end
    end

    def process_variant_image(variant, image_path)
      if(image_path.start_with? ('http'))
        io = open(image_path)
      else
        full_path = File.expand_path("../../../../#{image_path}", __FILE__)
        io = open(full_path)
      end

      image = Spree::Image.new
      image.viewable_type = 'Spree::Variant'
      image.viewable_id = variant.id

      filename = image_path.split("/").last

      image.attachment.attach(io: io, filename: filename)
      image.save

      p "save variant file image: #{image.attachment.blob.filename}"
    end

    def update_variant_stock(variant, row_index)
      stock_amount = @sheet.cell(row_index, 13)
      return if stock_amount.blank?

      stock_loc = stock_location(row_index)
      return if stock_loc.nil?

      stock_item = stock_loc.stock_items.where(variant_id: variant.id).first_or_create
      stock_item.adjust_count_on_hand(stock_amount)
    end

    def update_variant_price(variant, row_index)
      sale_price = @sheet.cell(row_index, 10)
      compare_at_price = @sheet.cell(row_index, 11)

      amount_money = Monetize.parse(sale_price)

      price = variant.prices.last

      price.amount = amount_money.amount
      price.currency = amount_money.currency.to_s

      if(compare_at_price.present?)
        compare_at_money = Monetize.parse(compare_at_price)
        price.compare_at_amount = compare_at_money.amount
      end

      price.save
    end

    def stock_location(row_index)

      stock_location_name = @sheet.cell(row_index, 12)
      return if stock_location_name.blank?
      Spree::StockLocation.where( name: stock_location_name).first_or_create
    end

    def variant_matched?(row_index, variant)
      values  = option_type_values(row_index)

      variant.option_values.each do |option_value|
        option_type_name = option_value.option_type.name
        option_value_name = option_value.name
        matched = values[option_type_name] != option_value_name
        return false if !matched
      end

      true
    end

    # {size: m, color: black}
    def option_type_values(row_index)

      result = {}
      option_type_columns.each do |option_type_name, column_index|
        result[option_type_name] = @sheet.cell(row_index, column_index)
      end

      result
    end

    # { size: col_x, colo: col_y }
    def option_type_columns
      return @option_types if !@option_types.nil?

      @option_types = {}

      (@sheet.last_column).times.each do |i|
        name = @sheet.cell(1, i+1)

        option_type_pattern = "OptionType "
        if(name.start_with?(option_type_pattern) )
          opton_type_name = name[option_type_pattern.length..-1]
          @option_types[opton_type_name] = i
        end
      end

      @option_types
    end

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


  end
end