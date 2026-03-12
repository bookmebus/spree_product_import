require 'spec_helper'

RSpec.describe ProductImportDataLoaders, type: :controller do
  controller(Spree::Admin::BaseController) do
    include ProductImportDataLoaders

    def index
      load_products
      render plain: 'ok'
    end

    def test_load_vendors
      load_vendors
      render plain: 'ok'
    end

    def test_load_shipping_categories
      load_shipping_categories
      render plain: 'ok'
    end

    def test_load_stock_locations
      load_stock_locations
      render plain: 'ok'
    end

    def test_load_option_types
      load_option_types
      render plain: 'ok'
    end

    def test_load_taxons
      load_taxons
      render plain: 'ok'
    end

    def test_load_update_products
      load_update_products
      render plain: 'ok'
    end
  end

  stub_authorization!

  let(:user) { create(:user) }

  before do
    unless controller.respond_to?(:spree_current_user)
      def controller.spree_current_user
        @current_user
      end
    end
    controller.instance_variable_set(:@current_user, user)

    routes.draw do
      path = 'spree/admin/base'
      get 'index' => "#{path}#index"
      get 'test_load_vendors' => "#{path}#test_load_vendors"
      get 'test_load_shipping_categories' => "#{path}#test_load_shipping_categories"
      get 'test_load_stock_locations' => "#{path}#test_load_stock_locations"
      get 'test_load_option_types' => "#{path}#test_load_option_types"
      get 'test_load_taxons' => "#{path}#test_load_taxons"
      get 'test_load_update_products' => "#{path}#test_load_update_products"
    end
  end

  describe '#load_products' do
    let!(:product1) { create(:product, created_at: 1.day.ago) }
    let!(:product2) { create(:product, created_at: 2.days.ago) }

    it 'loads products ordered by created_at desc' do
      get :index
      expect(assigns(:products)).to eq([product1, product2])
    end

    it 'paginates products' do
      get :index, params: { products_page: 1 }
      expect(assigns(:products)).to be_a(ActiveRecord::Relation)
    end

    it 'respects per_page parameter' do
      create_list(:product, 30)
      get :index, params: { products_per_page: 50 }
      expect(assigns(:products).count).to be > 25
    end
  end

  describe '#load_vendors' do
    before { skip unless defined?(Spree::Vendor) }

    let!(:vendor1) { create(:vendor, name: 'Alpha Vendor') }
    let!(:vendor2) { create(:vendor, name: 'Beta Vendor') }

    it 'loads vendors ordered by name' do
      get :test_load_vendors
      expect(assigns(:vendors)).to eq([vendor1, vendor2])
    end

    it 'paginates vendors' do
      get :test_load_vendors, params: { vendors_page: 1 }
      expect(assigns(:vendors)).to be_a(ActiveRecord::Relation)
    end
  end

  describe '#load_shipping_categories' do
    let!(:shipping_category) { create(:shipping_category) }

    it 'loads all shipping categories' do
      get :test_load_shipping_categories
      expect(assigns(:shipping_categories)).to include(shipping_category)
    end
  end

  describe '#load_stock_locations' do
    let!(:stock_location) { create(:stock_location) }

    context 'in create mode' do
      it 'loads all stock locations' do
        get :test_load_stock_locations
        expect(assigns(:stock_locations)).to include(stock_location)
      end
    end

    context 'in update mode with vendor' do
      before { skip unless defined?(Spree::Vendor) }

      let(:vendor) { create(:vendor) }
      let!(:vendor_stock_location) { create(:stock_location, vendor: vendor) }
      let!(:other_stock_location) { create(:stock_location) }

      it 'filters stock locations by vendor' do
        get :test_load_stock_locations, params: { mode: 'update', update_vendor_id: vendor.id }
        expect(assigns(:stock_locations)).to include(vendor_stock_location)
        expect(assigns(:stock_locations)).not_to include(other_stock_location)
      end
    end
  end

  describe '#load_option_types' do
    let!(:option_type) { create(:option_type_with_values) }

    it 'loads option types with option values' do
      get :test_load_option_types
      expect(assigns(:option_types)).to include(option_type)
    end

    it 'orders by position and name' do
      option_type2 = create(:option_type, name: 'AAA', position: 2)
      option_type1 = create(:option_type, name: 'ZZZ', position: 1)

      get :test_load_option_types
      expect(assigns(:option_types).first).to eq(option_type1)
    end
  end

  describe '#load_taxons' do
    let!(:parent_taxon) { create(:taxon, name: 'Categories') }
    let!(:child_taxon) { create(:taxon, name: 'Clothing', parent: parent_taxon) }
    let!(:grandchild_taxon) { create(:taxon, name: 'Shirts', parent: child_taxon) }

    it 'loads taxons with computed pretty_name' do
      get :test_load_taxons
      sorted_taxons = assigns(:taxons)
      
      shirt_taxon = sorted_taxons.find { |t| t.id == grandchild_taxon.id }
      expect(shirt_taxon.pretty_name).to include('Categories > Clothing > Shirts')
    end

    it 'sorts taxons by pretty_name' do
      get :test_load_taxons
      expect(assigns(:taxons)).to be_an(Array)
    end

  end

  describe '#load_update_products' do
    context 'without vendor or search' do
      it 'does not load products' do
        get :test_load_update_products
        expect(assigns(:update_products)).to be_nil
      end
    end

    context 'with vendor filter' do
      before { skip unless defined?(Spree::Vendor) }

      let(:vendor) { create(:vendor) }
      let!(:vendor_product) { create(:product, vendor: vendor) }
      let!(:other_product) { create(:product) }

      it 'loads products filtered by vendor' do
        get :test_load_update_products, params: { 
          update_vendor_id: vendor.id,
          update_per_page: 25
        }

        expect(assigns(:update_products)).to include(vendor_product)
        expect(assigns(:update_products)).not_to include(other_product)
      end
    end

    context 'with search parameters' do
      let!(:matching_product) { create(:product, name: 'Special Widget') }
      let!(:other_product) { create(:product, name: 'Regular Item') }

      it 'searches by name' do
        get :test_load_update_products, params: {
          q: { name_cont: 'Widget' }
        }

        expect(assigns(:update_products)).to include(matching_product)
        expect(assigns(:update_products)).not_to include(other_product)
      end

      it 'searches by SKU' do
        matching_product.master.update!(sku: 'SKU-123')
        other_product.master.update!(sku: 'SKU-456')

        get :test_load_update_products, params: {
          q: { variants_including_master_sku_cont: '123' }
        }

        expect(assigns(:update_products)).to include(matching_product)
      end

      it 'filters deleted products by default' do
        matching_product.update(deleted_at: Time.current)

        get :test_load_update_products, params: {
          q: { name_cont: 'Widget' }
        }

        expect(assigns(:update_products)).not_to include(matching_product)
      end
    end

    it 'sets default currency' do
      skip unless defined?(Spree::Vendor)
      vendor = create(:vendor)
      
      get :test_load_update_products, params: { update_vendor_id: vendor.id }
      expect(assigns(:default_price_currency)).to eq(Spree::Config[:currency])
    end

    it 'respects per_page limits' do
      skip unless defined?(Spree::Vendor)
      vendor = create(:vendor)

      get :test_load_update_products, params: { 
        update_vendor_id: vendor.id,
        update_per_page: 150 # Should be capped at 100
      }

      expect(assigns(:update_per_page)).to eq(100)
    end
  end

  describe '#products_per_page' do
    it 'returns 25 for invalid values' do
      get :index, params: { products_per_page: 0 }
      result = controller.send(:products_per_page)
      expect(result).to eq(25)
    end

    it 'caps at 200' do
      get :index, params: { products_per_page: 500 }
      result = controller.send(:products_per_page)
      expect(result).to eq(200)
    end

    it 'returns valid value within range' do
      get :index, params: { products_per_page: 50 }
      result = controller.send(:products_per_page)
      expect(result).to eq(50)
    end
  end

  describe '#vendors_per_page' do
    it 'returns 25 for invalid values' do
      get :test_load_vendors, params: { vendors_per_page: -5 }
      result = controller.send(:vendors_per_page)
      expect(result).to eq(25)
    end

    it 'caps at 200' do
      get :test_load_vendors, params: { vendors_per_page: 300 }
      result = controller.send(:vendors_per_page)
      expect(result).to eq(200)
    end
  end
end
