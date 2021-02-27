require 'roo'

module ProductImport
  MAIN_SHEET = "Main"
  VARIANT_SHEET = "Variant"

  class Importer

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
      p "file: #{file.path}"
      @xlsx ||= Roo::Spreadsheet.open(file)      
      import_product

    end

    def import_product
      # {sheet.last_row}, col: #{sheet.last_column}
      @xlsx.default_sheet = MAIN_SHEET
      @main_sheet  = @xlsx.sheet(MAIN_SHEET)

      if @main_sheet.last_row <= 1
        return mark_import_error(I18n.t('product_import.importer.file.no_data'))
      end

      rows_count = @main_sheet.last_row
      cols_count = @main_sheet.last_column

      # headers =  @main_sheet.row(1)

      p "rows: #{rows_count}, #{cols_count}"
      # p "vendor: #{@main_sheet.cell(2,1)}"

      p vendor
      p prototype
      p shipping_category
      p tax_category
      p "*" * 80
      p product_columns
      p property_columns
      p image_columns

    end

    def image_columns
      return @image_pattern if !@image_pattern.nil?
      @image_columns = []
      (@main_sheet.last_column).times.each do |i|
        name = @main_sheet.cell(1, i+1)
        image_pattern = "Main Image"
        if(name == image_pattern )
          @image_columns << i
        end
      end

      @image_columns
    end

    def product_columns
      {
        name: 5,
        sku: 6,
        description: 7,
        details: 8,
        price: 9,
        cost_price: 10,
        available_on: 11,
        discontinue_on: 12,
        meta_keywords: 13,
        meta_description: 14,
      }
    end

    def property_columns
      return @properties if !@properties.nil?

      @properties = {}

      (@main_sheet.last_column).times.each do |i|
        name = @main_sheet.cell(1, i+1)
        p "#{i+1}-#{name}"
        property_pattern = "Property "
        if(name.start_with?(property_pattern) )
          property_name = name[property_pattern.length..-1]
          @properties[property_name] = i
        end
      end

      @properties
    end

    def product_params(row_number)
  
      options = {
        name: @main_sheet.cell(row_number, 3),
        sku: @main_sheet.cell(row_number, 4),
        price: @main_sheet.cell(row_number, 8),
        
        cost_price: @main_sheet.cell(row_number, 10),
        available_on: @main_sheet.cell(row_number, 13),
        discontinue_on: @main_sheet.cell(row_number, 14),
        meta_keywords: @main_sheet.cell(row_number, 5),
        meta_description: @main_sheet.cell(row_number, 6),
      }

      compare_at_amount =  @main_sheet.cell(row_number, 9)

      product = Spree::Product.new(options)
      product.save

      # sequence(:name)   { |n| "Product ##{n} - #{Kernel.rand(9999)}" }
      # description       { generate(:random_description) }
      # price             { 19.99 }
      # cost_price        { 17.00 }
      # sku               { generate(:sku) }
      # available_on      { 1.year.ago }
      # deleted_at        { nil }
      # shipping_category { |r| Spree::ShippingCategory.first || r.association(:shipping_category) }
    end

    def shipping_category
      shipping_cat_name = @main_sheet.cell(2, 11)
      return nil if shipping_cat_name.blank?

      @shipping_category ||= Spree::ShippingCategory.find_by name: shipping_cat_name
    end

    def tax_category
      tax_cat_name = @main_sheet.cell(2, 12)
      return nil if tax_cat_name.blank?

      @tax_category ||= Spree::TaxCategory.find_by name: tax_cat_name
    end

    def prototype
      prototype_name = @main_sheet.cell(2, 2)
      return nil if prototype_name.blank?

      @prototype ||= Spree::Prototype.find_by name: prototype_name
    end

    def vendor
      vendor_name = @main_sheet.cell(2, 1)
      return nil if vendor_name.blank?

      @vendor ||= Spree::Vendor.find_by name: vendor_name
    end



    def mark_import_status(status)
      @product_import_file.status = status
      @product_import_file.save
    end

    def mark_import_error(error)
      @product_import_file.error = error
      mark_import_status(:failed)
    end


    def mark_import_in_progress
      # TODO: lock to avoid double process
      mark_import_status( :in_progress )
    end
  end
end