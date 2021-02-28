module ProductImport
  class VariantImporter
    VARIANT_SHEET = "Variant"
    
    def initialize(xlsx)
      @xlsx = xlsx
      @errors = {}
    end

    def call
      @errors = {}
      # {sheet.last_row}, col: #{sheet.last_column}
      @xlsx.default_sheet = VARIANT_SHEET
      @sheet = @xlsx.sheet(VARIANT_SHEET)

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

      p "master_sku: #{master_sku}"
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
        cost_currency: cost&.trycurrency&.to_s,
        product_id: product.id,
        tax_category_id: product.tax_category_id,
        vendor_id: product.vendor_id,
        is_master: false,
        track_inventory: true,
      }

      p "variant options: #{options}"

      found_variant = nil
      product.variants.includes(option_values: :option_type).each do |variant|
        if variant_matched?(row_index, variant)
          found_variant = variant
          break
        end
      end

      p "found_variant: #{found_variant}"

      found_variant.update(options)
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