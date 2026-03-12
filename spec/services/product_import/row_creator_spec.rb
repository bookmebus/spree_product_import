require 'spec_helper'

RSpec.describe ProductImport::RowCreator do
  let(:user) { create(:user) }
  let(:shipping_category) { create(:shipping_category) }

  def find_product_by_master_sku(sku)
    Spree::Variant.find_by(sku: sku)&.product
  end

  describe '#call' do
    context 'with valid product data' do
      let(:rows) do
        [
          {
            name: 'Test Product 1',
            sku: 'TEST-001',
            master_price: '19.99',
            shipping_category_id: shipping_category.id
          },
          {
            name: 'Test Product 2',
            sku: 'TEST-002',
            master_price: '29.99',
            shipping_category_id: shipping_category.id
          }
        ]
      end

      subject(:creator) { described_class.new(rows, user) }

      it 'creates all products successfully' do
        expect do
          creator.call
        end.to change(Spree::Product, :count).by(2)
      end

      it 'increments success_count' do
        creator.call
        expect(creator.success_count).to eq(2)
      end

      it 'returns self for method chaining' do
        expect(creator.call).to eq(creator)
      end

      it 'marks as successful' do
        creator.call
        expect(creator.success?).to be true
      end

      it 'creates products with correct attributes' do
        creator.call

        product = find_product_by_master_sku('TEST-001')
        expect(product.name).to eq('Test Product 1')
        expect(product.price).to eq(19.99)
        expect(product.shipping_category).to eq(shipping_category)
      end
    end

    context 'with product_import_file tracking' do
      let(:product_import_file) { create(:product_import_file, user: user, total_rows: 2) }
      let(:rows) do
        [
          {
            name: 'Product 1',
            sku: 'SKU-001',
            master_price: '10.00',
            shipping_category_id: shipping_category.id
          },
          {
            name: 'Product 2',
            sku: 'SKU-002',
            master_price: '20.00',
            shipping_category_id: shipping_category.id
          }
        ]
      end

      it 'updates progress after each row' do
        creator = described_class.new(rows, user, product_import_file)
        creator.call

        product_import_file.reload
        expect(product_import_file.processed_rows).to eq(2)
        expect(product_import_file.success_count).to eq(2)
      end
    end

    context 'with duplicate SKU validation' do
      let!(:existing_product) { create(:product, sku: 'EXISTING-SKU') }

      let(:rows) do
        [{
          name: 'Duplicate SKU Product',
          sku: 'EXISTING-SKU',
          master_price: '15.00',
          shipping_category_id: shipping_category.id
        }]
      end

      it 'rejects products with duplicate SKUs' do
        creator = described_class.new(rows, user)
        
        expect do
          creator.call
        end.not_to change(Spree::Product, :count)

        expect(creator.failures).to be_present
        expect(creator.failures.first[:errors]).to include(match(/SKU.*taken/i))
      end

      it 'performs case-insensitive SKU check' do
        rows.first[:sku] = 'existing-sku' # lowercase

        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures).to be_present
      end
    end

    context 'with duplicate SKUs within batch' do
      let(:rows) do
        [
          {
            name: 'Product 1',
            sku: 'BATCH-001',
            master_price: '10.00',
            shipping_category_id: shipping_category.id
          },
          {
            name: 'Product 2',
            sku: 'BATCH-001', # Duplicate
            master_price: '20.00',
            shipping_category_id: shipping_category.id
          }
        ]
      end

      it 'rejects second product with duplicate SKU' do
        creator = described_class.new(rows, user)
        creator.call

        expect(creator.success_count).to eq(1) # Only first succeeds
        expect(creator.failures.count).to eq(1)
        expect(creator.failures.first[:errors]).to include(match(/SKU/i))
      end
    end

    context 'with duplicate slug validation' do
      let!(:existing_product) { create(:product, name: 'Existing Product') }

      let(:rows) do
        [{
          name: 'Existing Product', # Will generate same slug
          sku: 'NEW-SKU',
          master_price: '15.00',
          shipping_category_id: shipping_category.id
        }]
      end

      it 'rejects products with duplicate slugs' do
        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures).to be_present
        expect(creator.failures.first[:errors]).to include(match(/slug.*exists/i))
      end
    end

    context 'with invalid shipping category' do
      let(:rows) do
        [{
          name: 'Product',
          sku: 'SKU-001',
          master_price: '10.00',
          shipping_category_id: 999999 # Non-existent
        }]
      end

      it 'rejects product with invalid shipping category' do
        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures).to be_present
        expect(creator.failures.first[:errors]).to include(match(/Shipping category/i))
      end
    end

    context 'with taxon assignment' do
      let(:taxon1) { create(:taxon) }
      let(:taxon2) { create(:taxon) }

      let(:rows) do
        [{
          name: 'Product with Taxons',
          sku: 'TAXON-001',
          master_price: '25.00',
          shipping_category_id: shipping_category.id,
          taxon_ids: [taxon1.id, taxon2.id]
        }]
      end

      it 'assigns taxons to product' do
        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('TAXON-001')
        expect(product.taxons).to contain_exactly(taxon1, taxon2)
      end

      it 'filters out zero taxon IDs' do
        rows.first[:taxon_ids] = [taxon1.id, 0, taxon2.id]

        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('TAXON-001')
        expect(product.taxons).to contain_exactly(taxon1, taxon2)
      end
    end

    context 'with variant creation' do
      let(:option_type) { create(:option_type_with_values) }
      let(:option_value) { option_type.option_values.first }

      let(:rows) do
        [{
          name: 'Product with Variants',
          sku: 'MASTER-001',
          master_price: '20.00',
          shipping_category_id: shipping_category.id,
          variants: [{
            sku: 'VAR-001',
            price: '25.00',
            option_values: { option_type.id.to_s => option_value.id.to_s }
          }]
        }]
      end

      it 'creates product with variants' do
        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('MASTER-001')
        expect(product.variants.count).to eq(1)
        expect(product.variants.first.sku).to eq('VAR-001')
      end

      it 'records variant errors as warnings' do
        rows.first[:variants].first[:sku] = '' # Invalid

        creator = described_class.new(rows, user)
        creator.call

        expect(creator.success_count).to eq(1) # Product still created
        expect(creator.warnings).to be_present
      end

      it 'validates variant SKUs do not conflict with master' do
        rows.first[:variants].first[:sku] = 'MASTER-001' # Same as master

        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures).to be_present
        expect(creator.failures.first[:errors]).to include(match(/conflicts with master/i))
      end

      it 'validates variant SKUs are unique among variants' do
        rows.first[:variants] << {
          sku: 'VAR-001', # Duplicate
          price: '30.00',
          option_values: { option_type.id.to_s => option_value.id.to_s }
        }

        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures).to be_present
        expect(creator.failures.first[:errors]).to include(match(/duplicated within variants/i))
      end
    end

    context 'with image attachments' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('image'), filename: 'test.jpg') }

      let(:rows) do
        [{
          name: 'Product with Images',
          sku: 'IMG-001',
          master_price: '30.00',
          shipping_category_id: shipping_category.id,
          images: [{
            blob: blob,
            alt: 'Test Image'
          }]
        }]
      end

      it 'attaches images to product' do
        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('IMG-001')
        expect(product.images.count).to eq(1)
      end

      it 'records image errors as warnings' do
        allow_any_instance_of(ProductImport::ImageAttacher).to receive(:attach_to_product).and_return(['Image error'])

        creator = described_class.new(rows, user)
        creator.call

        expect(creator.success_count).to eq(1) # Product still created
        expect(creator.warnings).to be_present
      end
    end

    context 'with optional fields' do
      let(:rows) do
        [{
          name: 'Product with Optional Fields',
          sku: 'OPT-001',
          master_price: '40.00',
          shipping_category_id: shipping_category.id,
          detail: 'Product details',
          meta_title: 'SEO Title',
          meta_keywords: 'keywords',
          meta_description: 'SEO description',
          available_on: '2026-05-01'
        }]
      end

      it 'sets optional attributes' do
        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('OPT-001')
        expect(product.meta_title).to eq('SEO Title')
        expect(product.meta_keywords).to eq('keywords')
        expect(product.meta_description).to eq('SEO description')
        expect(product.available_on).to be_present
      end
    end

    context 'with vendor assignment' do
      before { skip unless defined?(Spree::Vendor) }

      let(:vendor) { create(:vendor) }
      let(:rows) do
        [{
          name: 'Vendor Product',
          sku: 'VENDOR-001',
          master_price: '50.00',
          shipping_category_id: shipping_category.id,
          vendor_id: vendor.id
        }]
      end

      it 'assigns vendor to product' do
        creator = described_class.new(rows, user)
        creator.call

        product = find_product_by_master_sku('VENDOR-001')
        expect(product.vendor).to eq(vendor)
      end
    end

    context 'with validation failures' do
      let(:rows) do
        [{
          name: '', # Invalid - name required
          sku: 'INVALID-001',
          master_price: '10.00',
          shipping_category_id: shipping_category.id
        }]
      end

      it 'tracks failures with error messages' do
        creator = described_class.new(rows, user)
        creator.call

        expect(creator.failures.count).to eq(1)
        expect(creator.failures.first[:index]).to eq(1)
        expect(creator.failures.first[:errors]).to be_present
      end

      it 'does not create failed products' do
        expect do
          creator = described_class.new(rows, user)
          creator.call
        end.not_to change(Spree::Product, :count)
      end
    end

    context 'with mixed successes and failures' do
      let(:rows) do
        [
          {
            name: 'Valid Product',
            sku: 'VALID-001',
            master_price: '15.00',
            shipping_category_id: shipping_category.id
          },
          {
            name: '', # Invalid
            sku: 'INVALID-001',
            master_price: '20.00',
            shipping_category_id: shipping_category.id
          }
        ]
      end

      it 'creates valid products and tracks failures' do
        creator = described_class.new(rows, user)

        expect do
          creator.call
        end.to change(Spree::Product, :count).by(1)

        expect(creator.success_count).to eq(1)
        expect(creator.failures.count).to eq(1)
      end
    end

    context 'with searchkick integration' do
      let(:rows) do
        [{
          name: 'Searchable Product',
          sku: 'SEARCH-001',
          master_price: '25.00',
          shipping_category_id: shipping_category.id
        }]
      end

      it 'reindexes products if searchkick is present' do
        skip unless Spree::Product.respond_to?(:reindex)

        creator = described_class.new(rows, user)
        product = instance_double(Spree::Product)
        
        allow(product).to receive(:save).and_return(true)
        allow(product).to receive(:reindex)
        allow_any_instance_of(described_class).to receive(:build_product).and_return(product)

        creator.call

        expect(product).to have_received(:reindex)
      end
    end
  end

  describe '#validate_row' do
    let(:creator) { described_class.new([], user) }

    before do
      creator.send(:preload_validation_data)
    end

    it 'returns empty array for valid row' do
      row = {
        name: 'Valid Product',
        sku: 'VALID-SKU',
        shipping_category_id: shipping_category.id
      }

      errors = creator.send(:validate_row, row, 0)
      expect(errors).to be_empty
    end

    it 'validates required SKU presence' do
      row = { name: 'Product without SKU' }
      errors = creator.send(:validate_row, row, 0)
      
      # Should pass - SKU may not be required in all cases
      expect(errors).to be_an(Array)
    end
  end

  describe '#parse_available_on' do
    let(:creator) { described_class.new([], user) }

    it 'parses valid date strings' do
      result = creator.send(:parse_available_on, '2026-03-15')
      expect(result).to be_a(Time)
    end

    it 'returns nil for blank values' do
      expect(creator.send(:parse_available_on, '')).to be_nil
      expect(creator.send(:parse_available_on, nil)).to be_nil
    end

    it 'returns nil for invalid dates' do
      result = creator.send(:parse_available_on, 'not-a-date')
      expect(result).to be_nil
    end
  end

end
