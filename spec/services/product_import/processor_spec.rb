require 'spec_helper'
require 'spree_multi_vendor/factories'

RSpec.describe ProductImport::Processor, type: :services do
  let!(:vendor) { create(:vendor, name: "Zando Fashion") }
  let!(:prototype) { create(:prototype, name: 'Men Shirt') }
  let!(:shipping_category) { create(:shipping_category, name: 'Shipping by VTENH')}
  let!(:shipping_category_exp) { create(:shipping_category, name: 'Shipping by Express')}
  let!(:tax_category) { create(:tax_category, name: 'VAT Incl.')}

  let!(:stock_location_1) { create(:stock_location, name: 'SLP1', backorderable_default: true, propagate_all_variants: true)}
  let!(:stock_location_2) { create(:stock_location, name: 'SLP2', backorderable_default: true, propagate_all_variants: true)}
  # stock_location.stock_items.where(variant_id: product_1.master_id).first.adjust_count_on_hand(10)

  let!(:taxon_men) { create(:taxon, name: 'Menware')}
  let!(:taxon_women) { create(:taxon, name: 'Womenware')}

  # color: black, white, red
  let!(:option_type_color) { create(:option_type, name: 'color', presentation: 'Color') }
  let!(:option_value_blue) { create(:option_value, option_type: option_type_color, name: 'blue', presentation: '#0000ff' )}
  let!(:option_value_white) { create(:option_value, option_type: option_type_color, name: 'white', presentation: '#ffffff' )}
  let!(:option_value_red) { create(:option_value, option_type: option_type_color, name: 'red', presentation: '#ff0000' )}

  #size: m, l
  let!(:option_type_size) { create(:option_type, name: 'size', presentation: 'Size') }
  let!(:option_value_medium) { create(:option_value, option_type: option_type_size, name: 'M', presentation: 'M' )}
  let!(:option_value_large) { create(:option_value, option_type: option_type_size, name: 'L', presentation: 'L' )}

  let!(:prop_type) { create(:property, name: 'Type')}
  let!(:prop_material) { create(:property, name: 'Material')}
  let!(:prop_brand) { create(:property, name: 'Brand')}

  let!(:prototype) do
    properties = [ prop_type, prop_material, prop_brand ]
    option_types = [ option_type_color, option_type_size]
    taxons = [taxon_men, taxon_women]

    create(:prototype, name: 'Shirt', properties: properties, option_types: option_types, taxons: taxons)
  end

  describe ".call" do
    describe 'file is invalid' do
      before(:each) do
        import_file = create(:product_import_file_error)
        @processor = ProductImport::Processor.new(import_file)
        @processor.call
      end

      it "imports with error" do
        expect( @processor.success? ).to eq false
        expect(@processor.errors.present?).to eq true
        expect(@processor.product_import_file.failed?).to eq true
        expect(@processor.product_import_file.error.present?).to eq true
      end
    end

    describe 'file is valid' do
      before(:each) do
        import_file = create(:product_import_file_ok)
        @processor = ProductImport::Processor.new(import_file)
        @processor.call
        @products = Spree::Product.all.to_a
      end

      it "import data and make product_import_file to status to eq :success" do
        expect( @processor.success? ).to eq true
        expect(@processor.errors.present?).to eq false
        expect(@processor.product_import_file.success?).to eq true
        expect(@processor.product_import_file.error.blank?).to eq true
      end

      it "creates 2 products" do
        expect(@products.size).to eq 2

        product1 = @products[0]
        expect(product1.name).to eq "Summer 2021 Tshirt"
        expect(product1.description).to eq "Trendy Tshirt for your summer need."
        expect(product1.slug).to eq "summer-2021-tshirt"
        expect(product1.promotionable).to eq false
        expect(product1.available_on.present?).to eq true 
        expect(product1.discontinue_on.iso8601).to eq '2022-02-12T00:00:00Z'
    
        expect(product1.meta_title).to eq 'Title Nike, Zando, T-shirt'
        expect(product1.meta_description).to eq nil
        expect(product1.meta_keywords).to eq 'Nike, Zando, T-shirt'
    
        expect(product1.tax_category_id).to eq tax_category.id
        expect(product1.shipping_category_id).to eq shipping_category.id
        expect(product1.vendor_id).to eq vendor.id


        product2 = @products[1]
        expect(product2.name).to eq "Winter 2021 Tshirt"
        expect(product2.description).to eq "Trendy Womenware summer need."
        expect(product2.slug).to eq "winter-2021-tshirt"
        expect(product2.promotionable).to eq true
        expect(product2.available_on.iso8601).to eq "2022-02-27T00:00:00Z" 
        expect(product2.discontinue_on.iso8601).to eq '2023-03-10T00:00:00Z'
    
        expect(product2.meta_title).to eq 'Winter 2021 Tshirt'
        expect(product2.meta_description).to eq 'Beautiful Winter 2021 Tshirt'
        expect(product2.meta_keywords).to eq 'Winter 2021 Tshirt'
    
        expect(product2.tax_category_id).to eq tax_category.id
        expect(product2.shipping_category_id).to eq shipping_category_exp.id
        expect(product2.vendor_id).to eq vendor.id
      end

      it 'create 3 product properties for product1' do
        product1 = @products[0]

        names =  product1.properties.map(&:name)
        expect(names).to eq ["Type", "material", "condition"]

        values = product1.product_properties.map(&:value)
        expect(values).to eq ["T-shirt", "Cotton", "Fare"]
      end

      it 'create 2 product properties for product2' do
        product2 = @products[1]

        names =  product2.properties.map(&:name)
        expect(names).to eq ["material", "condition"]

        values = product2.product_properties.map(&:value)
        expect(values).to eq [ "Cotton", "Good"]
      end

      it "creates 2 master variants for product1 and product2 respectively " do
        product1 = @products[0]
        # first product master variant details
        expect(product1.master.sku).to eq "ZFMST202121"
        expect(product1.master.cost_price).to eq 10.0
        expect(product1.master.cost_currency).to eq 'USD'
        expect(product1.master.track_inventory).to eq true
        expect(product1.master.tax_category_id).to eq nil # master variant does not have tax_category
        expect(product1.master.vendor_id).to eq vendor.id

        # first product master variant images
        filenames =  product1.master.images.map { |image| image.attachment.blob.filename.to_s }
        expect(filenames).to eq ["product-1.jpeg", "product-2.jpeg"]

        # first product master variant prices
        expect(product1.master.prices.first.amount).to eq 11.2
        expect(product1.master.prices.first.compare_at_amount).to eq 15.0
        expect(product1.master.prices.first.currency).to eq 'USD'

        # first product master variant stock items
        product1_stocks = product1.master.stock_items.map(&:count_on_hand)
        expect(product1_stocks).to eq [0, 5]

        product2 = @products[1]
        # second product master variant details
        expect(product2.master.sku).to eq "WTST202121"
        expect(product2.master.cost_price).to eq 12.0
        expect(product2.master.cost_currency).to eq 'USD'
        expect(product2.master.track_inventory).to eq true
        expect(product2.master.tax_category_id).to eq nil # master variant does not have tax_category
        expect(product2.master.vendor_id).to eq vendor.id

        # second product master variant images
        filenames =  product2.master.images.map { |image| image.attachment.blob.filename.to_s }
        expect(filenames).to eq ["product-2.jpeg"]

        # second product master variant prices
        expect(product2.master.prices.first.amount).to eq 15.0
        expect(product2.master.prices.first.compare_at_amount).to eq 18.0
        expect(product2.master.prices.first.currency).to eq 'USD'

        # second product master variant stock items
        product2_stocks = product2.master.stock_items.map(&:count_on_hand)
        expect(product2_stocks).to eq [0, 10]
      end

      it "creates 6 variants for product1 with options type ( color: 3 x size: 2) and 2 variants updated" do
        product1 = @products[0]
        p1_variants = product1.variants.to_a
        expect(p1_variants.size).to eq 6

        variant_red_large = p1_variants.select{|v| v.sku == "ZFMST202121RedLarge" }.first
        expect(variant_red_large).to be_present
        expect(variant_red_large.option_values.to_a).to eq [option_value_red, option_value_large]

        red_large_stock = variant_red_large.stock_items.map(&:count_on_hand)
        expect(red_large_stock).to eq [0, 30]

        price_red_large =  variant_red_large.prices.last
        expect(price_red_large.amount).to eq 11.2
        expect(price_red_large.compare_at_amount).to eq 15.0
        expect(price_red_large.currency).to eq 'USD'

        red_large_filenames = variant_red_large.images.map{|image| image.attachment.blob.filename.to_s }
        expect(red_large_filenames).to eq ["variant-1.jpeg", "variant-2.jpg"]

        variant_red_medium = p1_variants.select{|v| v.sku == "ZFMST202121RedMedium" }.first
        expect(variant_red_medium).to be_present
        expect(variant_red_medium.option_values.to_a).to eq [option_value_red, option_value_medium]
        
        red_medium_stock = variant_red_medium.stock_items.map(&:count_on_hand)
        expect(red_medium_stock).to eq [0, 50]

        price_red_medium = variant_red_medium.prices.last
        expect(price_red_medium.amount).to eq 15.0
        expect(price_red_medium.compare_at_amount).to eq 18.0

        red_medium_filenames = variant_red_medium.images.map{|image| image.attachment.blob.filename.to_s }
        expect(red_medium_filenames).to eq ["variant-2.jpg", "variant-1.jpeg"]

        expect(variant_red_large.weight).to eq 0.5 
        expect(variant_red_medium.weight).to eq 0.6 

        expect(variant_red_large.height).to eq 0.4 
        expect(variant_red_medium.height).to eq 0.5 


        expect(variant_red_large.width).to eq 0.1
        expect(variant_red_medium.width).to eq 0.2

        expect(variant_red_large.depth).to eq 1.2
        expect(variant_red_medium.depth).to eq 1.3

        expect(variant_red_large.cost_price).to eq 10.0
        expect(variant_red_medium.cost_price).to eq 10.1 

        expect(variant_red_large.cost_currency).to eq 'USD'
        expect(variant_red_medium.cost_currency).to eq 'USD'

        expect(variant_red_large.discontinue_on.iso8601).to eq '2022-10-30T00:00:00Z'
        expect(variant_red_medium.discontinue_on.iso8601).to eq '2022-11-01T00:00:00Z'

        expect(variant_red_large.tax_category_id).to eq product1.tax_category_id
        expect(variant_red_medium.tax_category_id).to eq product1.tax_category_id 

        expect(variant_red_large.vendor_id).to eq product1.vendor_id
        expect(variant_red_medium.vendor_id).to eq product1.vendor_id
      end

      it "creates 3 variants for product2 with option type ( color: 3) and 1 variant updated" do
        product2 = @products[1]
        variants = product2.variants.to_a

        expect(variants.size).to eq 3

        expect(variants[1].option_values).to eq [option_value_blue]

        stock = variants[1].stock_items.map(&:count_on_hand)
        expect(stock).to eq [0, 1]

        price = variants[1].prices.first
        expect(price.amount).to eq 13.1
        expect(price.compare_at_amount).to eq 15.5
        expect(price.currency).to eq 'USD'

        expect(variants[1].option_values).to eq [option_value_blue]

        expect(variants[0].sku).to be_blank 
        expect(variants[1].sku).to eq 'ZFMST202121BlueS' 
        expect(variants[2].sku).to be_blank 

        expect(variants[0].weight).to eq 0.0 
        expect(variants[1].weight).to eq 0.7 
        expect(variants[2].weight).to eq 0.0 

        expect(variants[0].height).to eq nil 
        expect(variants[1].height).to eq 0.6 
        expect(variants[2].height).to eq nil

        expect(variants[0].width).to eq nil
        expect(variants[1].width).to eq 0.3
        expect(variants[2].width).to eq nil

        expect(variants[0].depth).to eq nil
        expect(variants[1].depth).to eq 1.4
        expect(variants[2].depth).to eq nil

        expect(variants[0].cost_price).to eq nil
        expect(variants[1].cost_price).to eq 10.2 
        expect(variants[2].cost_price).to eq nil

        expect(variants[0].cost_currency).to eq 'USD'
        expect(variants[1].cost_currency).to eq 'USD'
        expect(variants[2].cost_currency).to eq 'USD'

        expect(variants[0].discontinue_on).to eq nil
        expect(variants[1].discontinue_on.iso8601).to eq '2022-11-01T00:00:00Z'
        expect(variants[2].discontinue_on).to eq nil


        expect(variants[0].tax_category_id).to eq nil
        expect(variants[1].tax_category_id).to eq product2.tax_category_id 
        expect(variants[2].tax_category_id).to eq nil

        expect(variants[0].vendor_id).to eq product2.vendor_id
        expect(variants[1].vendor_id).to eq product2.vendor_id
        expect(variants[2].vendor_id).to eq product2.vendor_id
      end
    end
  end
end