require 'spec_helper'

RSpec.describe ProductImport::BulkUpdater do
  let(:user) { create(:admin_user) }
  let(:ability) { Spree::Ability.new(user) }
  let!(:product1) { create(:product, name: 'Product 1', price: 10.00) }
  let!(:product2) { create(:product, name: 'Product 2', price: 20.00) }
  let(:shipping_category) { create(:shipping_category) }

  describe '#call' do
    context 'with basic attribute updates' do
      let(:update_rows) do
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

      subject(:updater) { described_class.new(update_rows, ability) }

      it 'updates selected products' do
        updater.call

        product1.reload
        expect(product1.name).to eq('Updated Product 1')
        expect(product1.price).to eq(99.99)
      end

      it 'increments update_count for successful updates' do
        updater.call
        expect(updater.update_count).to eq(2)
      end

      it 'returns self for method chaining' do
        expect(updater.call).to eq(updater)
      end
    end

    context 'with unselected products' do
      let(:update_rows) do
        {
          product1.id.to_s => {
            name: 'Should Update',
            _selected: '1'
          },
          product2.id.to_s => {
            name: 'Should Not Update',
            _selected: '0'
          }
        }
      end

      it 'skips unselected products' do
        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        product2.reload

        expect(product1.name).to eq('Should Update')
        expect(product2.name).to eq('Product 2') # Unchanged
      end
    end

    context 'with taxon updates' do
      let(:taxon1) { create(:taxon) }
      let(:taxon2) { create(:taxon) }

      let(:update_rows) do
        {
          product1.id.to_s => {
            taxon_ids: [taxon1.id, taxon2.id],
            _selected: '1'
          }
        }
      end

      it 'updates product taxons' do
        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.taxons).to contain_exactly(taxon1, taxon2)
      end

      it 'filters out zero values' do
        update_rows[product1.id.to_s][:taxon_ids] = [taxon1.id, 0, taxon2.id]

        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.taxons).to contain_exactly(taxon1, taxon2)
      end
    end

    context 'with variant updates' do
      let(:variant) { create(:variant, product: product1, sku: 'VAR-001', price: 25.00) }

      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            variants: {
              variant.id.to_s => {
                sku: 'VAR-UPDATED',
                price: '30.00',
                cost_price: '15.00',
                weight: '2.5'
              }
            }
          }
        }
      end

      it 'updates existing variant attributes' do
        updater = described_class.new(update_rows, ability)
        updater.call

        variant.reload
        expect(variant.sku).to eq('VAR-UPDATED')
        expect(variant.price).to eq(30.00)
        expect(variant.cost_price).to eq(15.00)
        expect(variant.weight).to eq(2.5)
      end

      it 'updates variant price' do
        updater = described_class.new(update_rows, ability)
        updater.call

        variant.reload
        expect(variant.default_price.amount).to eq(30.00)
      end

      it 'updates compare_at_price' do
        update_rows[product1.id.to_s][:variants][variant.id.to_s][:compare_at_price] = '50.00'

        updater = described_class.new(update_rows, ability)
        updater.call

        variant.reload
        expect(variant.default_price.compare_at_amount).to eq(50.00)
      end
    end

    context 'with master variant updates' do
      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            variants: {
              product1.master.id.to_s => {
                sku: 'MASTER-UPDATED',
                price: '100.00'
              }
            }
          }
        }
      end

      it 'updates master variant' do
        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.master.sku).to eq('MASTER-UPDATED')
        expect(product1.price).to eq(100.00)
      end
    end

    context 'with new variant creation' do
      let(:option_type) { create(:option_type_with_values) }
      let(:option_value) { option_type.option_values.first }

      before do
        product1.option_types << option_type
      end

      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            new_variants: {
              '0' => {
                sku: 'NEW-VAR-001',
                price: '45.00',
                option_values: { option_type.id.to_s => option_value.id.to_s }
              }
            }
          }
        }
      end

      it 'creates new variants' do
        expect do
          updater = described_class.new(update_rows, ability)
          updater.call
        end.to change { product1.variants.count }.by(1)

        product1.reload
        new_variant = product1.variants.find_by(sku: 'NEW-VAR-001')
        expect(new_variant).to be_present
        expect(new_variant.price).to eq(45.00)
      end

      it 'captures variant creation errors' do
        # Set SKU to match the product's SKU to trigger conflict error
        update_rows[product1.id.to_s][:new_variants]['0'][:sku] = product1.sku

        updater = described_class.new(update_rows, ability)
        updater.call

        expect(updater.errors[product1.id]).to be_present
      end
    end

    context 'with image attachments' do
      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            new_images: {
              '0' => {
                url: 'https://example.com/image.jpg',
                alt: 'Product Image'
              }
            }
          }
        }
      end

      it 'attaches new images' do
        allow_any_instance_of(ProductImport::ImageAttacher).to receive(:attach_to_product).and_return([])

        updater = described_class.new(update_rows, ability)
        updater.call

        expect(updater.update_count).to eq(1)
      end

      it 'captures image attachment errors' do
        allow_any_instance_of(ProductImport::ImageAttacher).to receive(:attach_to_product).and_return(['Image error'])

        updater = described_class.new(update_rows, ability)
        updater.call

        expect(updater.errors[product1.id]).to include('Image error')
      end
    end

    context 'with stock level updates' do
      let(:stock_location) { create(:stock_location) }
      let(:variant) { product1.master }

      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            stock_updates: {
              variant.id.to_s => {
                stock_location_id: stock_location.id,
                quantity: '100'
              }
            }
          }
        }
      end

      it 'updates stock levels' do
        updater = described_class.new(update_rows, ability)
        updater.call

        stock_item = stock_location.stock_items.find_by(variant: variant)
        expect(stock_item.count_on_hand).to eq(100)
      end

      it 'creates stock item if it does not exist' do
        # Ensure no stock item exists for this variant at this location
        existing_stock_item = stock_location.stock_items.find_by(variant: variant)
        existing_stock_item&.destroy
        
        expect do
          updater = described_class.new(update_rows, ability)
          updater.call
        end.to change { stock_location.stock_items.where(variant: variant).count }.from(0).to(1)
        
        stock_item = stock_location.stock_items.find_by(variant: variant)
        expect(stock_item.count_on_hand).to eq(100)
      end
    end

    context 'with SEO attribute updates' do
      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            meta_title: 'SEO Title',
            meta_keywords: 'seo, keywords',
            meta_description: 'SEO Description'
          }
        }
      end

      it 'updates SEO fields' do
        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.meta_title).to eq('SEO Title')
        expect(product1.meta_keywords).to eq('seo, keywords')
        expect(product1.meta_description).to eq('SEO Description')
      end

      it 'allows clearing meta fields with empty strings' do
        product1.update(meta_title: 'Old Title')
        update_rows[product1.id.to_s][:meta_title] = ''

        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.meta_title).to eq('')
      end
    end

    context 'with vendor updates' do
      before { skip unless defined?(Spree::Vendor) }

      let(:vendor) { create(:vendor) }
      let(:update_rows) do
        {
          product1.id.to_s => {
            _selected: '1',
            vendor_id: vendor.id
          }
        }
      end

      it 'updates vendor' do
        updater = described_class.new(update_rows, ability)
        updater.call

        product1.reload
        expect(product1.vendor_id).to eq(vendor.id)
      end
    end

    context 'with validation errors' do
      let(:update_rows) do
        {
          product1.id.to_s => {
            shipping_category_id: 999999, # Non-existent ID will cause FK constraint or association error
            _selected: '1'
          }
        }
      end

      it 'tracks error count' do
        updater = described_class.new(update_rows, ability)
        updater.call

        expect(updater.error_count).to eq(1)
        expect(updater.update_count).to eq(0)
      end

      it 'stores error messages' do
        updater = described_class.new(update_rows, ability)
        updater.call

        expect(updater.errors[product1.id]).to be_present
      end
    end

    context 'with inaccessible products' do
      let(:other_user) { create(:user) }
      let(:other_ability) { Spree::Ability.new(other_user) }
      let(:update_rows) do
        {
          product1.id.to_s => {
            name: 'Should Not Update',
            _selected: '1'
          }
        }
      end

      before do
        # Simulate product being inaccessible
        allow(Spree::Product).to receive(:accessible_by).with(other_ability, :update).and_return(Spree::Product.none)
      end

      it 'skips inaccessible products' do
        updater = described_class.new(update_rows, other_ability)
        updater.call

        expect(updater.update_count).to eq(0)
      end
    end
  end

  describe '#success?' do
    it 'returns true when no errors' do
      updater = described_class.new({}, ability)
      expect(updater.success?).to be true
    end

    it 'returns false when errors exist' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@error_count, 1)
      expect(updater.success?).to be false
    end
  end

  describe '#partial_success?' do
    it 'returns true when both updates and errors exist' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@update_count, 2)
      updater.instance_variable_set(:@error_count, 1)
      expect(updater.partial_success?).to be true
    end

    it 'returns false when only updates exist' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@update_count, 2)
      expect(updater.partial_success?).to be false
    end
  end

  describe '#flash_message' do
    it 'returns success message when all succeeded' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@update_count, 2)

      message = updater.flash_message
      expect(message[:type]).to eq(:success)
      expect(message[:message]).to include('Successfully updated 2')
    end

    it 'returns error message when all failed' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@error_count, 2)

      message = updater.flash_message
      expect(message[:type]).to eq(:error)
    end

    it 'returns warning message for partial success' do
      updater = described_class.new({}, ability)
      updater.instance_variable_set(:@update_count, 3)
      updater.instance_variable_set(:@error_count, 1)

      message = updater.flash_message
      expect(message[:type]).to eq(:warning)
      expect(message[:message]).to include('Updated 3')
      expect(message[:message]).to include('1')
      expect(message[:message]).to include('failed')
    end
  end

  describe '#parse_available_on' do
    let(:updater) { described_class.new({}, ability) }

    it 'parses valid date strings' do
      result = updater.send(:parse_available_on, '2026-01-15')
      expect(result).to be_a(Time)
    end

    it 'returns nil for blank values' do
      result = updater.send(:parse_available_on, '')
      expect(result).to be_nil
    end

    it 'handles nil gracefully' do
      result = updater.send(:parse_available_on, nil)
      expect(result).to be_nil
    end

    it 'returns nil for invalid date strings' do
      result = updater.send(:parse_available_on, 'invalid-date')
      expect(result).to be_nil
    end
  end
end
