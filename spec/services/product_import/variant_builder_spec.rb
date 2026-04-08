require 'spec_helper'

RSpec.describe ProductImport::VariantBuilder do
  let(:product) { create(:product, sku: 'MASTER-SKU') }
  let(:option_type) { create(:option_type_with_values) }
  let(:option_value1) { option_type.option_values.first }
  let(:option_value2) { option_type.option_values.second }

  subject(:builder) { described_class.new(product) }

  describe '#create_variants' do
    context 'with valid variant data' do
      let(:variants_data) do
        [{
          sku: 'VAR-001',
          price: '25.00',
          cost_price: '12.50',
          weight: '2.5',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'creates variant successfully' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.variants.count }.by(1)
      end

      it 'sets variant attributes' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-001')

        expect(variant.sku).to eq('VAR-001')
        expect(variant.cost_price).to eq(12.50)
        expect(variant.weight).to eq(2.5)
      end

      it 'creates variant price' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-001')

        expect(variant.price).to eq(25.00)
        expect(variant.default_price).to be_present
      end

      it 'assigns option values' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-001')

        expect(variant.option_values).to include(option_value1)
      end

      it 'adds option types to product' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.option_types.count }.by(1)
      end

      it 'returns empty errors array on success' do
        errors = builder.create_variants(variants_data)
        expect(errors).to be_empty
      end
    end

    context 'with multiple variants' do
      let(:variants_data) do
        [
          {
            sku: 'VAR-001',
            price: '25.00',
            option_values: { option_type.id.to_s => option_value1.id.to_s }
          },
          {
            sku: 'VAR-002',
            price: '30.00',
            option_values: { option_type.id.to_s => option_value2.id.to_s }
          }
        ]
      end

      it 'creates multiple variants' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.variants.count }.by(2)
      end

      it 'adds option type only once' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.option_types.count }.by(1)
      end
    end

    context 'with compare_at_price' do
      let(:variants_data) do
        [{
          sku: 'VAR-SALE',
          price: '20.00',
          compare_at_price: '30.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'sets compare_at_price on variant price' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-SALE')

        expect(variant.default_price.compare_at_amount).to eq(30.00)
      end
    end

    context 'with existing option types on product' do
      before do
        product.option_types << option_type
      end

      let(:variants_data) do
        [{
          sku: 'VAR-001',
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'does not duplicate option types' do
        expect do
          builder.create_variants(variants_data)
        end.not_to change { product.option_types.count }
      end
    end

    context 'with SKU conflicts with master' do
      let(:variants_data) do
        [{
          sku: 'MASTER-SKU', # Same as product SKU
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'returns validation error' do
        errors = builder.create_variants(variants_data)
        expect(errors).to include(match(/conflicts with master/i))
      end

      it 'does not create variant' do
        expect do
          builder.create_variants(variants_data)
        end.not_to change { product.variants.count }
      end
    end

    context 'with duplicate SKUs among variants' do
      let(:variants_data) do
        [
          {
            sku: 'DUPLICATE-SKU',
            price: '25.00',
            option_values: { option_type.id.to_s => option_value1.id.to_s }
          },
          {
            sku: 'DUPLICATE-SKU', # Duplicate
            price: '30.00',
            option_values: { option_type.id.to_s => option_value2.id.to_s }
          }
        ]
      end

      it 'returns validation error' do
        errors = builder.create_variants(variants_data)
        expect(errors).to include(match(/duplicated within variants/i))
      end

      it 'does not create any variants' do
        expect do
          builder.create_variants(variants_data)
        end.not_to change { product.variants.count }
      end
    end

    context 'with case-insensitive SKU validation' do
      let(:variants_data) do
        [
          {
            sku: 'Var-001',
            price: '25.00',
            option_values: { option_type.id.to_s => option_value1.id.to_s }
          },
          {
            sku: 'VAR-001', # Same SKU, different case
            price: '30.00',
            option_values: { option_type.id.to_s => option_value2.id.to_s }
          }
        ]
      end

      it 'detects case-insensitive duplicates' do
        errors = builder.create_variants(variants_data)
        expect(errors).to include(match(/duplicated/i))
      end
    end

    context 'with invalid variant data' do
      let(:variants_data) do
        [{
          sku: '', # Invalid - blank SKU
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'returns validation error' do
        errors = builder.create_variants(variants_data)
        expect(errors).to be_present
      end
    end

    context 'with missing option values' do
      let(:variants_data) do
        [{
          sku: 'VAR-001',
          price: '25.00',
          option_values: {} # No option values
        }]
      end

      it 'does not create variant' do
        expect do
          builder.create_variants(variants_data)
        end.not_to change { product.variants.count }
      end
    end

    context 'with non-existent option values' do
      let(:variants_data) do
        [{
          sku: 'VAR-001',
          price: '25.00',
          option_values: { option_type.id.to_s => '999999' } # Non-existent
        }]
      end

      it 'does not create variant' do
        expect do
          builder.create_variants(variants_data)
        end.not_to change { product.variants.count }
      end
    end

    context 'with ActionController::Parameters input' do
      let(:variants_data) do
        [ActionController::Parameters.new(
          sku: 'VAR-PARAMS',
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        )]
      end

      it 'handles Parameters objects correctly' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.variants.count }.by(1)
      end
    end

    context 'with hash input (string keys)' do
      let(:variants_data) do
        [{
          'sku' => 'VAR-STRING',
          'price' => '25.00',
          'option_values' => { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'handles string-keyed hashes' do
        expect do
          builder.create_variants(variants_data)
        end.to change { product.variants.count }.by(1)
      end
    end

    context 'with additional variant attributes' do
      let(:tax_category) { create(:tax_category) }
      let(:variants_data) do
        [{
          sku: 'VAR-FULL',
          price: '25.00',
          cost_price: '10.00',
          weight: '1.5',
          height: '10.0',
          width: '5.0',
          depth: '3.0',
          tax_category_id: tax_category.id,
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      it 'sets all variant dimensions' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-FULL')

        expect(variant.height).to eq(10.0)
        expect(variant.width).to eq(5.0)
        expect(variant.depth).to eq(3.0)
      end

      it 'sets tax category' do
        builder.create_variants(variants_data)
        variant = product.variants.find_by(sku: 'VAR-FULL')

        expect(variant.tax_category).to eq(tax_category)
      end
    end

    context 'with nil or blank input' do
      it 'returns empty array for nil' do
        expect(builder.create_variants(nil)).to eq([])
      end

      it 'returns empty array for empty array' do
        expect(builder.create_variants([])).to eq([])
      end

      it 'returns empty array for non-array input' do
        expect(builder.create_variants('invalid')).to eq([])
      end
    end

    context 'when option type cannot be added to product' do
      let(:variants_data) do
        [{
          sku: 'VAR-001',
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      before do
        allow(product).to receive(:save).and_return(false)
        allow(product).to receive_message_chain(:errors, :full_messages).and_return(['Error'])
      end

      it 'returns error about option types' do
        errors = builder.create_variants(variants_data)
        expect(errors).to include(match(/Failed to add option types/i))
      end
    end

    context 'when variant save fails' do
      let(:variants_data) do
        [{
          sku: 'VAR-FAIL',
          price: '25.00',
          option_values: { option_type.id.to_s => option_value1.id.to_s }
        }]
      end

      before do
        create(:variant, product: product, sku: 'VAR-FAIL')
      end

      it 'returns validation error' do
        errors = builder.create_variants(variants_data)
        expect(errors).to be_present
      end
    end
  end

end
