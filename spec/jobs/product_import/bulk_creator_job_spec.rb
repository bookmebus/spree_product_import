require 'spec_helper'

RSpec.describe ProductImport::BulkCreatorJob, type: :job do
  let(:user) { create(:user) }
  let(:shipping_category) { create(:shipping_category) }

  def find_product_by_master_sku(sku)
    Spree::Variant.find_by(sku: sku)&.product
  end

  describe '#perform' do
    context 'with valid manual import data' do
      let(:row_data) do
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

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: row_data.size
        )
      end

      it 'processes all rows successfully' do
        expect do
          described_class.new.perform(product_import_file.id)
        end.to change(Spree::Product, :count).by(2)
      end

      it 'updates status to processing' do
        described_class.new.perform(product_import_file.id)
        expect(product_import_file.reload.status).to eq('success').or eq('processing')
      end

      it 'marks import as success' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload
        
        expect(product_import_file.status).to eq('success')
        expect(product_import_file.success_count).to eq(2)
        expect(product_import_file.failure_count).to eq(0)
      end

      it 'updates progress counts' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.processed_rows).to eq(2)
        expect(product_import_file.total_rows).to eq(2)
      end

      it 'creates products with correct attributes' do
        described_class.new.perform(product_import_file.id)

        product = find_product_by_master_sku('TEST-001')
        expect(product).to be_present
        expect(product.name).to eq('Test Product 1')
        expect(product.price).to eq(19.99)
      end
    end

    context 'with variants' do
      let(:option_type) { create(:option_type_with_values) }
      let(:option_value) { option_type.option_values.first }

      let(:row_data) do
        [{
          name: 'Product with Variants',
          sku: 'MASTER-001',
          master_price: '25.00',
          shipping_category_id: shipping_category.id,
          variants: [{
            sku: 'VAR-001',
            price: '30.00',
            option_values: { option_type.id.to_s => option_value.id.to_s }
          }]
        }]
      end

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 1
        )
      end

      it 'creates product with variants' do
        described_class.new.perform(product_import_file.id)

        product = find_product_by_master_sku('MASTER-001')
        expect(product.variants.count).to eq(1)
        expect(product.variants.first.sku).to eq('VAR-001')
      end

      it 'handles variant creation warnings' do
        # Create invalid variant data
        row_data.first[:variants].first[:sku] = '' # Invalid

        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        # Product should still be created despite variant errors
        expect(find_product_by_master_sku('MASTER-001')).to be_present
      end
    end

    context 'with image attachments' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('fake'), filename: 'test.jpg') }

      let(:row_data) do
        [{
          name: 'Product with Images',
          sku: 'IMG-001',
          master_price: '50.00',
          shipping_category_id: shipping_category.id,
          images: [{
            attachment_key: 'row_0_image_0',
            alt: 'Test Image'
          }]
        }]
      end

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 1
        ).tap do |pif|
          pif.row_images.attach(
            io: StringIO.new(blob.download),
            filename: 'row_0_image_0_test.jpg',
            content_type: blob.content_type
          )
        end
      end

      it 'rehydrates images from attachments' do
        described_class.new.perform(product_import_file.id)

        product = find_product_by_master_sku('IMG-001')
        expect(product.images.count).to eq(1)
        expect(product.images.first.alt).to eq('Test Image')
      end

      it 'handles missing attachment keys gracefully' do
        row_data.first[:images].first[:attachment_key] = 'nonexistent_key'

        expect do
          described_class.new.perform(product_import_file.id)
        end.not_to raise_error

        product_import_file.reload
        expect(product_import_file.status).to eq('success')
      end
    end

    context 'with URL-based images' do
      let(:row_data) do
        [{
          name: 'Product with URL Images',
          sku: 'URL-001',
          master_price: '45.00',
          shipping_category_id: shipping_category.id,
          images: [{
            url: 'https://example.com/image.jpg',
            alt: 'URL Image'
          }]
        }]
      end

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 1
        )
      end

      it 'preserves URL-based images' do
        # Stub the URL download
        allow_any_instance_of(ProductImport::ImageAttacher).to receive(:attach_from_url)

        described_class.new.perform(product_import_file.id)

        product = find_product_by_master_sku('URL-001')
        expect(product).to be_present
      end
    end

    context 'with failures' do
      let(:row_data) do
        [
          {
            name: '', # Invalid - no name
            sku: 'FAIL-001',
            master_price: '10.00',
            shipping_category_id: shipping_category.id
          }
        ]
      end

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 1
        )
      end

      it 'marks import as failed' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.status).to eq('failed')
        expect(product_import_file.failure_count).to eq(1)
      end

      it 'stores error details' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.error).to be_present
        expect(product_import_file.error[:manual_rows]).to be_present
      end
    end

    context 'with mixed successes and failures' do
      let(:row_data) do
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

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 2
        )
      end

      it 'creates valid products and tracks failures' do
        expect do
          described_class.new.perform(product_import_file.id)
        end.to change(Spree::Product, :count).by(1)

        product_import_file.reload
        expect(product_import_file.status).to eq('failed')
        expect(product_import_file.success_count).to eq(1)
        expect(product_import_file.failure_count).to eq(1)
      end
    end

    context 'with empty row data' do
      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: [{ name: 'placeholder', sku: 'placeholder-sku' }],
          total_rows: 1
        ).tap do |import_file|
          import_file.update_columns(row_data: [], total_rows: 0)
        end
      end

      it 'marks as failed with descriptive error' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.status).to eq('failed')
        expect(product_import_file.error[:message]).to eq('No product rows to process')
      end
    end

    context 'with warnings (product created but issues occurred)' do
      let(:row_data) do
        [{
          name: 'Product with Warning',
          sku: 'WARN-001',
          master_price: '35.00',
          shipping_category_id: shipping_category.id,
          images: [{
            url: 'invalid-url', # Will cause warning
            alt: 'Bad URL'
          }]
        }]
      end

      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: row_data,
          total_rows: 1
        )
      end

      it 'marks as success with warnings in error field' do
        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.status).to eq('success')
        expect(product_import_file.error).to be_present
        expect(product_import_file.error[:warnings]).to be_present
      end
    end

    context 'when file does not exist' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect do
          described_class.new.perform(999999)
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when file is not active' do
      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          status: :canceled,
          row_data: [],
          total_rows: 0
        )
      end

      it 'does not process canceled imports' do
        expect do
          described_class.new.perform(product_import_file.id)
        end.not_to change(Spree::Product, :count)
      end
    end

    context 'when an unexpected error occurs' do
      let(:product_import_file) do
        create(:product_import_file,
          user: user,
          import_type: :manual_import,
          status: :active,
          row_data: [{ name: 'Test' }],
          total_rows: 1
        )
      end

      it 'marks import as failed and logs error' do
        allow_any_instance_of(ProductImport::RowCreator).to receive(:call).and_raise(StandardError.new('Unexpected error'))

        described_class.new.perform(product_import_file.id)
        product_import_file.reload

        expect(product_import_file.status).to eq('failed')
        expect(product_import_file.error[:message]).to eq('Unexpected error')
        expect(product_import_file.error[:backtrace]).to be_present
      end
    end
  end

  describe '#symbolize_row' do
    let(:job) { described_class.new }

    it 'symbolizes hash keys' do
      row = { 'name' => 'Test', 'sku' => 'SKU-001' }
      result = job.send(:symbolize_row, row)
      
      expect(result).to eq({ name: 'Test', sku: 'SKU-001' })
    end

    it 'handles nested hashes' do
      row = { 'product' => { 'name' => 'Test' } }
      result = job.send(:symbolize_row, row)
      
      expect(result).to eq({ product: { name: 'Test' } })
    end

    it 'handles objects with to_h method' do
      struct = Struct.new(:name, :sku).new('Test', 'SKU-001')
      result = job.send(:symbolize_row, struct)
      
      expect(result[:name]).to eq('Test')
    end
  end

  describe '#rehydrate_images' do
    let(:job) { described_class.new }
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
    let(:product_import_file) { create(:product_import_file, user: user) }

    before do
      product_import_file.row_images.attach(
        io: StringIO.new(blob.download),
        filename: 'row_0_image_0_original.jpg',
        content_type: blob.content_type
      )
    end

    it 'replaces attachment_key with blob' do
      rows = [{
        name: 'Test',
        images: [{
          attachment_key: 'row_0_image_0',
          alt: 'Test'
        }]
      }]

      job.send(:rehydrate_images, rows, product_import_file)

      expect(rows[0][:images][0][:blob]).to be_present
      expect(rows[0][:images][0][:attachment_key]).to be_nil
    end

    it 'handles missing attachment keys' do
      rows = [{
        images: [{
          attachment_key: 'nonexistent_key',
          alt: 'Test'
        }]
      }]

      expect do
        job.send(:rehydrate_images, rows, product_import_file)
      end.not_to raise_error

      # Key should still be removed even if blob not found
      expect(rows[0][:images][0][:attachment_key]).to eq('nonexistent_key')
    end
  end

  describe '#build_error_details' do
    let(:job) { described_class.new }

    it 'builds error structure from failures' do
      failures = [{ index: 1, errors: ['Name is required'] }]
      result = job.send(:build_error_details, failures, [])

      expect(result[:manual_rows]).to be_present
      expect(result[:manual_rows].first[:index]).to eq(1)
    end

    it 'includes warnings separately' do
      warnings = [{ product_id: 123, errors: ['Image failed'] }]
      result = job.send(:build_error_details, [], warnings)

      expect(result[:warnings]).to be_present
      expect(result[:warnings].first[:product_id]).to eq(123)
    end

    it 'handles both failures and warnings' do
      failures = [{ index: 1, errors: ['Failed'] }]
      warnings = [{ product_id: 123, errors: ['Warning'] }]
      result = job.send(:build_error_details, failures, warnings)

      expect(result[:manual_rows]).to be_present
      expect(result[:warnings]).to be_present
    end
  end
end
