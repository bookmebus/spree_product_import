module ProductImport
  class VariantImporter < BaseImporter

    def call
      super

      if @handler.rows_count <= 1
        return @errors[:variant] = I18n.t('product_import.importer.file.no_variant_data')
      end

      rows_count = @handler.rows_count

      body_rows_count = rows_count - 1
      body_offset = 2

      body_rows_count.times.each do |index|
        row_index = index + body_offset
        import_row(row_index)
      end
    end

    def import_row(row_index)
      master_sku = @handler.cell(row_index, 1)
      master_variant = Spree::Variant.where(is_master: true).find_by(sku: master_sku)

      if(master_variant.nil?)
        @errors[:variant] ||= {}
        @errors[:variant][row_index.to_s] = "sku: #{master_sku} no found" 
        return
      end

      sku = @handler.cell(row_index, 2)
      position = @handler.cell(row_index, 3)
      weight = @handler.cell(row_index, 4)
      height = @handler.cell(row_index, 5)
      width = @handler.cell(row_index, 6)
      depth = @handler.cell(row_index, 7)
      discontinue_on = @handler.cell(row_index, 8)
      cost_value = @handler.cell(row_index, 9)
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
      update_variant_images(matched_variant, row_index)
    end

    def update_variant_stock(variant, row_index)
      stock_amount = @handler.cell(row_index, 13)
      return if stock_amount.blank?

      stock_loc = stock_location(row_index)
      return if stock_loc.nil?

      stock_item = stock_loc.stock_items.where(variant_id: variant.id).first_or_create
      stock_item.adjust_count_on_hand(stock_amount)
    end

    def update_variant_price(variant, row_index)
      sale_price = @handler.cell(row_index, 10)
      compare_at_price = @handler.cell(row_index, 11)

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

      stock_location_name = @handler.cell(row_index, 12)
      return if stock_location_name.blank?
      Spree::StockLocation.where( name: stock_location_name).first_or_create
    end

    def variant_matched?(row_index, variant)
      values  = option_type_values(row_index)

      # v = variant.option_values.to_a.map do |option_value|
      #   "#{option_value.option_type.name}-#{option_value.name}"
      # end

      # p v

      variant.option_values.each do |option_value|
        option_type_name = option_value.option_type.name.downcase
        option_value_name = option_value.name.downcase
        matched = values[option_type_name] == option_value_name
        return false if !matched
      end

      true
    end

    # {size: m, color: black}
    def option_type_values(row_index)

      result = {}
      option_type_columns.each do |option_type_name, column_index|
        result[option_type_name] = @handler.cell(row_index, column_index).downcase
      end

      result
    end

    # { size: col_x, color: col_y }
    def option_type_columns
      return @option_types if !@option_types.nil?

      @option_types = {}

      (@handler.cols_count).times.each do |i|
        name = @handler.cell(1, i+1)

        option_type_pattern = "OptionType "
        if(name.start_with?(option_type_pattern) )
          opton_type_name = name[option_type_pattern.length..-1]
          @option_types[opton_type_name.downcase] = i+1
        end
      end

      @option_types
    end
  end
end