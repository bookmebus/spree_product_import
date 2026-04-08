require 'spec_helper'

RSpec.describe Spree::Admin::ProductImportFilesController, type: :controller do
  stub_authorization!

  let(:user) { create(:user) }
  let(:vendor) { create(:vendor) if defined?(Spree::Vendor) }
  let!(:shipping_category) { create(:shipping_category) }
  let!(:taxon) { create(:taxon) }
  let!(:option_type) { create(:option_type_with_values) }

  before do
    # Define spree_current_user method if it doesn't exist
    unless controller.respond_to?(:spree_current_user)
      def controller.spree_current_user
        @current_user
      end
    end
    controller.instance_variable_set(:@current_user, user)
  end

  describe 'GET #index' do
    let!(:import_file1) { create(:product_import_file, user: user, status: :active) }
    let!(:import_file2) { create(:product_import_file, user: user, status: :success) }

    it 'loads product import files' do
      get :index
      expect(response).to have_http_status(:success)
      expect(assigns(:collection)).to include(import_file1, import_file2)
    end

    it 'filters by status' do
      get :index, params: { q: { status: '4' } } # success status
      expect(assigns(:collection)).to include(import_file2)
    end

    it 'paginates results' do
      get :index, params: { page: 1 }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET #new' do
    context 'in create mode' do
      it 'initializes a new product import file' do
        get :new
        expect(assigns(:product_import_file)).to be_a_new(Spree::ProductImportFile)
        expect(assigns(:mode)).to eq('create')
      end

      it 'provides default product import rows' do
        get :new
        expect(assigns(:product_import_rows)).to be_an(Array)
        expect(assigns(:product_import_rows).first).to include(:name, :sku, :_selected)
      end

      it 'loads required data' do
        get :new
        expect(assigns(:shipping_categories)).to be_present
        expect(assigns(:option_types)).to be_present
        expect(assigns(:taxons)).to be_present
      end
    end

    context 'in update mode' do
      it 'sets update mode' do
        get :new, params: { mode: 'update' }
        expect(assigns(:mode)).to eq('update')
      end

      it 'does not load update products without vendor or search params' do
        get :new, params: { mode: 'update' }
        expect(assigns(:update_products)).to be_nil
      end

      context 'with vendor filter' do
        before { skip unless defined?(Spree::Vendor) }

        it 'loads products for the vendor' do
          product = create(:product, vendor: vendor)
          get :new, params: { mode: 'update', update_vendor_id: vendor.id }
          expect(assigns(:update_products)).to include(product)
        end
      end

      context 'with search params' do
        let!(:product) { create(:product, name: 'Special Widget') }

        it 'loads products matching search' do
          get :new, params: { mode: 'update', q: { name_cont: 'Widget' } }
          expect(assigns(:update_products)).to include(product)
        end
      end
    end
  end

  describe 'POST #create' do
    context 'single file import' do
      let(:file) { fixture_file_upload('spec/support/data/products.csv', 'text/csv') }

      it 'creates a file import and enqueues background job' do
        expect do
          post :create, params: {
            product_import_file: {
              name: 'Test Import',
              file: file
            }
          }
        end.to change(Spree::ProductImportFile, :count).by(1)

        expect(response).to redirect_to(admin_product_import_files_path)
        expect(flash[:success]).to be_present
      end

      it 'sets import type to file_import' do
        post :create, params: {
          product_import_file: {
            name: 'Test Import',
            file: file
          }
        }
        expect(Spree::ProductImportFile.last.import_type).to eq('file_import')
      end

      it 'associates import with current user' do
        post :create, params: {
          product_import_file: {
            name: 'Test Import',
            file: file
          }
        }
        expect(Spree::ProductImportFile.last.user).to eq(user)
      end
    end

    context 'multiple manual rows' do
      let(:row_params) do
        {
          '0' => {
            name: 'Product 1',
            sku: 'SKU-001',
            master_price: '19.99',
            shipping_category_id: shipping_category.id,
            _selected: '1'
          },
          '1' => {
            name: 'Product 2',
            sku: 'SKU-002',
            master_price: '29.99',
            shipping_category_id: shipping_category.id,
            _selected: '1'
          }
        }
      end

      it 'creates manual import and enqueues background job' do
        expect do
          post :create, params: {
            import_name: 'Manual Import',
            product_import_files: row_params
          }
        end.to change(Spree::ProductImportFile, :count).by(1)

        import = Spree::ProductImportFile.last
        expect(import.import_type).to eq('manual_import')
        expect(import.row_data).to be_present
        expect(import.total_rows).to eq(2)
      end

      it 'filters unselected rows' do
        row_params['1'][:_selected] = '0'

        post :create, params: {
          import_name: 'Manual Import',
          product_import_files: row_params
        }

        import = Spree::ProductImportFile.last
        expect(import.total_rows).to eq(1)
      end

      it 'filters rows without data' do
        row_params['2'] = { _selected: '1' } # No actual data

        post :create, params: {
          import_name: 'Manual Import',
          product_import_files: row_params
        }

        import = Spree::ProductImportFile.last
        expect(import.total_rows).to eq(2)
      end
    end

    context 'Excel import parsed by UI' do
      let(:excel_file) { fixture_file_upload('spec/support/data/products.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }
      let(:row_params) do
        {
          '0' => {
            name: 'Excel Product',
            sku: 'EXCEL-001',
            master_price: '49.99',
            shipping_category_id: shipping_category.id,
            _selected: '1'
          }
        }
      end

      it 'creates import with Excel file attached' do
        expect do
          post :create, params: {
            xlsx_import_file: excel_file,
            xlsx_import_name: 'Excel Import',
            product_import_files: row_params
          }
        end.to change(Spree::ProductImportFile, :count).by(1)

        import = Spree::ProductImportFile.last
        expect(import.file).to be_attached
        expect(import.row_data).to be_present
      end
    end

    context 'empty submission' do
      it 'shows error and re-renders form' do
        post :create, params: { product_import_files: {} }

        expect(response).to render_template(:new)
        expect(flash.now[:error]).to be_present
      end
    end
  end

  describe 'POST #bulk_update' do
    let!(:product1) { create(:product, name: 'Product 1') }
    let!(:product2) { create(:product, name: 'Product 2') }

    let(:update_params) do
      {
        product1.id.to_s => {
          name: 'Updated Product 1',
          master_price: '99.99',
          _selected: '1'
        },
        product2.id.to_s => {
          name: 'Updated Product 2',
          _selected: '1'
        }
      }
    end

    it 'updates selected products' do
      post :bulk_update, params: { product_updates: update_params }

      product1.reload
      expect(product1.name).to eq('Updated Product 1')
      expect(product1.price).to eq(99.99)
    end

    it 'skips unselected products' do
      update_params[product2.id.to_s][:_selected] = '0'
      original_name = product2.name

      post :bulk_update, params: { product_updates: update_params }

      product2.reload
      expect(product2.name).to eq(original_name)
    end

    it 'redirects back to update mode' do
      post :bulk_update, params: { 
        product_updates: update_params,
        update_vendor_id: vendor&.id,
        update_per_page: 50
      }

      expect(response).to redirect_to(new_admin_product_import_file_path(
        mode: 'update',
        update_vendor_id: vendor&.id,
        update_per_page: 50
      ))
    end

    it 'shows success message when all updates succeed' do
      post :bulk_update, params: { product_updates: update_params }
      expect(flash[:success]).to be_present
    end

    it 'shows error message when updates fail' do
      # Create a duplicate product to cause SKU uniqueness validation error
      create(:product, sku: 'DUPLICATE-SKU')
      update_params[product1.id.to_s][:sku] = 'DUPLICATE-SKU'

      post :bulk_update, params: { product_updates: update_params }
      expect(flash[:error] || flash[:warning]).to be_present
    end
  end

  describe 'private methods' do
    describe '#filter_params' do
      it 'permits name and file' do
        params = ActionController::Parameters.new(
          product_import_file: { name: 'Test', file: 'file.csv', unauthorized: 'value' }
        )
        allow(controller).to receive(:params).and_return(params)

        result = controller.send(:filter_params)
        expect(result.keys).to match_array(['name', 'file'])
      end
    end

    describe '#normalize_rows_array' do
      it 'handles array input' do
        result = controller.send(:normalize_rows_array, [{ name: 'Test' }])
        expect(result).to be_an(Array)
      end

      it 'converts hash to array of values' do
        result = controller.send(:normalize_rows_array, { '0' => { name: 'Test' } })
        expect(result).to eq([{ name: 'Test' }])
      end

      it 'returns empty array for invalid input' do
        result = controller.send(:normalize_rows_array, 'invalid')
        expect(result).to eq([])
      end
    end

    describe '#row_selected?' do
      it 'returns true for "1"' do
        expect(controller.send(:row_selected?, { _selected: '1' })).to be true
      end

      it 'returns true for "true"' do
        expect(controller.send(:row_selected?, { _selected: 'true' })).to be true
      end

      it 'returns true for "on"' do
        expect(controller.send(:row_selected?, { _selected: 'on' })).to be true
      end

      it 'returns false for "0"' do
        expect(controller.send(:row_selected?, { _selected: '0' })).to be false
      end
    end

    describe '#row_has_data?' do
      it 'returns true when row has data' do
        expect(controller.send(:row_has_data?, { name: 'Test', _selected: '1' })).to be true
      end

      it 'returns false when only _selected is present' do
        expect(controller.send(:row_has_data?, { _selected: '1' })).to be false
      end

      it 'returns false for empty row' do
        expect(controller.send(:row_has_data?, { name: '', sku: '', _selected: '1' })).to be false
      end
    end

    describe '#default_product_import_row' do
      it 'returns hash with default fields' do
        result = controller.send(:default_product_import_row)
        expect(result).to include(:name, :sku, :master_price, :_selected)
        expect(result[:_selected]).to eq('1')
      end
    end
  end

  describe 'GET #option_types' do
    it 'returns option types as JSON' do
      get :option_types, format: :json
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first).to include('id', 'name', 'presentation', 'option_values')
    end
  end

  describe 'GET #stock_locations' do
    let!(:stock_location) { create(:stock_location) }

    it 'returns all active stock locations when no vendor_id given' do
      get :stock_locations, format: :json
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.map { |sl| sl['id'] }).to include(stock_location.id)
    end

    context 'filtered by vendor_id' do
      before { skip unless defined?(Spree::Vendor) }

      let(:vendor) { create(:vendor) }
      let!(:vendor_location) { create(:stock_location, vendor: vendor) }
      let!(:other_location) { create(:stock_location) }

      it 'returns only locations for the given vendor' do
        get :stock_locations, params: { vendor_id: vendor.id }, format: :json
        json = JSON.parse(response.body)
        ids = json.map { |sl| sl['id'] }
        expect(ids).to include(vendor_location.id)
        expect(ids).not_to include(other_location.id)
      end
    end
  end
end
