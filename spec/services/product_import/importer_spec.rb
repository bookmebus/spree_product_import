require 'spec_helper'
require 'spree_multi_vendor/factories'

RSpec.describe ProductImport::Importer, type: :services do
  let!(:vendor) { create(:vendor, name: "Zando Fashion") }
  let!(:prototype) { create(:prototype, name: 'Men Shirt') }
  let!(:shipping_category) { create(:shipping_category, name: 'Shipping by VTENH')}
  let!(:tax_category) { create(:tax_category, name: 'VAT Incl.')}

  let!(:stock_location_1) { create(:stock_location, name: 'SLP1', backorderable_default: true, propagate_all_variants: true)}
  let!(:stock_location_2) { create(:stock_location, name: 'SLP2', backorderable_default: true, propagate_all_variants: true)}
  # stock_location.stock_items.where(variant_id: product_1.master_id).first.adjust_count_on_hand(10)

  let!(:taxon_men) { create(:taxon, name: 'Menware')}
  let!(:taxon_women) { create(:taxon, name: 'Womenware')}

  # color: black, white, red
  let!(:option_type_color) { create(:option_type, name: 'color', presentation: 'Color') }
  let!(:option_value_black) { create(:option_value, option_type: option_type_color, name: 'black', presentation: '#000000' )}
  let!(:option_value_white) { create(:option_value, option_type: option_type_color, name: 'white', presentation: '#ffffff' )}
  let!(:option_value_red) { create(:option_value, option_type: option_type_color, name: 'red', presentation: '#ff0000' )}

  #size: m, l
  let!(:option_type_size) { create(:option_type, name: 'size', presentation: 'Size') }
  let!(:option_value_medium) { create(:option_value, option_type: option_type_size, name: 'medium', presentation: 'M' )}
  let!(:option_value_large) { create(:option_value, option_type: option_type_size, name: 'large', presentation: 'L' )}

  let!(:prop_type) { create(:property, name: 'Type')}
  let!(:prop_material) { create(:property, name: 'Material')}
  let!(:prop_brand) { create(:property, name: 'Brand')}

  # name         { 'Baseball Cap' }
  # properties   { [create(:property)] }
  # option_types { [create(:option_type)] } 

  let!(:prototype) do
    properties = [ prop_type, prop_material, prop_brand ]
    option_types = [ option_type_color, option_type_size]
    taxons = [taxon_men, taxon_women]

    create(:prototype, name: 'Shirt', properties: properties, option_types: option_types, taxons: taxons)
  end

  describe "" do
    it "read" do
      import_file = create(:product_import_file)
      importer = ProductImport::Importer.new(import_file)
      importer.call

      # Spree::Product.all.map{|p| display_product(p)}
      display_product(Spree::Product.last)
    end

    def display_product(product)
      p product.master.stock_items
      p product.master.prices
      p "*" * 80
      variant =  product.variants.first
      p variant
      p variant
      p "option_values"
      p variant.option_values
      
      p "\noption_value_variants"
      p variant.option_value_variants

      p "stock_items"
      p variant.stock_items
      p "prices"
      p variant.prices
    end
  end
end