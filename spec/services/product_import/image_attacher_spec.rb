require 'spec_helper'

RSpec.describe ProductImport::ImageAttacher do
  subject(:attacher) { described_class.new }

  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product) }

  describe '#attach_to_product' do
    context 'with file upload' do
      let(:file) { fixture_file_upload('spec/support/data/product-2.jpeg', 'image/jpeg') }
      let(:images_data) do
        [{
          file: file,
          alt: 'Test Image'
        }]
      end

      it 'attaches image to product master variant' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end

      it 'sets alt text on image' do
        attacher.attach_to_product(product, images_data)
        image = product.master.images.first

        expect(image.alt).to eq('Test Image')
      end

      it 'returns empty errors array on success' do
        errors = attacher.attach_to_product(product, images_data)
        expect(errors).to be_empty
      end
    end

    context 'with ActiveStorage blob' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
      let(:images_data) do
        [{
          blob: blob,
          alt: 'Blob Image'
        }]
      end

      it 'attaches blob directly without duplication' do
        attacher.attach_to_product(product, images_data)
        image = product.master.images.first

        expect(image.attachment.blob).to eq(blob)
      end

      it 'is more efficient than file upload' do
        # Blob attachment should not create duplicate blob
        blob
        initial_blob_count = ActiveStorage::Blob.count

        attacher.attach_to_product(product, images_data)

        expect(ActiveStorage::Blob.count).to eq(initial_blob_count)
      end
    end

    context 'with URL-based image' do
      let(:images_data) do
        [{
          url: 'https://example.com/image.jpg',
          alt: 'URL Image'
        }]
      end

      before do
        allow(URI).to receive(:open).with('https://example.com/image.jpg').and_return(StringIO.new('fake image data'))
      end

      it 'downloads and attaches image from URL' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end

      it 'sets alt text' do
        attacher.attach_to_product(product, images_data)
        image = product.master.images.first

        expect(image.alt).to eq('URL Image')
      end
    end

    context 'with failed URL download' do
      let(:images_data) do
        [{
          url: 'https://example.com/nonexistent.jpg',
          alt: 'Failed Image'
        }]
      end

      before do
        allow(URI).to receive(:open).with('https://example.com/nonexistent.jpg')
          .and_raise(OpenURI::HTTPError.new('404 Not Found', StringIO.new('not found')))
      end

      it 'returns error message' do
        errors = attacher.attach_to_product(product, images_data)
        expect(errors).to include(match(/Failed to download/i))
      end

      it 'does not attach image' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.not_to change { product.master.images.count }
      end
    end

    context 'with multiple images' do
      let(:blob1) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test1'), filename: 'test1.jpg') }
      let(:blob2) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test2'), filename: 'test2.jpg') }

      let(:images_data) do
        [
          { blob: blob1, alt: 'Image 1' },
          { blob: blob2, alt: 'Image 2' }
        ]
      end

      it 'attaches all images' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(2)
      end
    end

    context 'with hash input' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
      let(:images_data) do
        {
          '0' => { blob: blob, alt: 'Hash Image' }
        }
      end

      it 'converts hash to array and attaches' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end
    end

    context 'with ActionController::Parameters' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
      let(:images_data) do
        ActionController::Parameters.new(
          '0' => { blob: blob, alt: 'Params Image' }
        )
      end

      it 'handles Parameters objects' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end
    end

    context 'with blank or nil input' do
      it 'returns empty errors for nil' do
        errors = attacher.attach_to_product(product, nil)
        expect(errors).to be_empty
      end

      it 'returns empty errors for empty array' do
        errors = attacher.attach_to_product(product, [])
        expect(errors).to be_empty
      end
    end

    context 'with missing file/blob/url' do
      let(:images_data) do
        [{ alt: 'No Source' }]
      end

      it 'returns error message' do
        errors = attacher.attach_to_product(product, images_data)
        expect(errors).to include(match(/No file, blob, or URL/i))
      end
    end

    context 'with image save failure' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
      let(:images_data) do
        [{ blob: blob, alt: 'Failing Image' }]
      end

      before do
        allow_any_instance_of(Spree::Image).to receive(:save).and_return(false)
        allow_any_instance_of(Spree::Image).to receive_message_chain(:errors, :full_messages).and_return(['Validation failed'])
      end

      it 'returns error message' do
        errors = attacher.attach_to_product(product, images_data)
        expect(errors).to include(match(/Validation failed/i))
      end
    end

    context 'with alternative key names' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }

      it 'accepts :attachment key for file' do
        images_data = [{ attachment: blob }]
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end

      it 'accepts :image key for file' do
        images_data = [{ image: blob }]
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end

      it 'accepts :image_url key for URL' do
        images_data = [{ image_url: 'https://example.com/image.jpg' }]
          allow(URI).to receive(:open).with('https://example.com/image.jpg').and_return(StringIO.new('image'))

        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)
      end

      it 'accepts :alt_text key for alt' do
        images_data = [{ blob: blob, alt_text: 'Alternative Alt' }]
        attacher.attach_to_product(product, images_data)

        expect(product.master.images.first.alt).to eq('Alternative Alt')
      end
    end
  end

  describe '#attach_to_variant' do
    context 'with valid image data' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }
      let(:images_data) do
        [{ blob: blob, alt: 'Variant Image' }]
      end

      it 'attaches image to variant' do
        expect do
          attacher.attach_to_variant(variant, images_data)
        end.to change { variant.images.count }.by(1)
      end

      it 'does not attach to product master' do
        expect do
          attacher.attach_to_variant(variant, images_data)
        end.not_to change { product.master.images.count }
      end
    end
  end

  describe 'URL filename extraction' do
    let(:attacher) { described_class.new }

    it 'extracts filename from URL path' do
      url = 'https://example.com/products/image.jpg'
      filename = attacher.send(:extract_filename_from_url, url)
      
      expect(filename).to eq('image.jpg')
    end

    it 'handles URLs with query parameters' do
      url = 'https://example.com/image.jpg?size=large'
      filename = attacher.send(:extract_filename_from_url, url)
      
      expect(filename).to eq('image.jpg')
    end

    it 'falls back to timestamped filename for invalid URLs' do
      url = 'invalid-url'
      filename = attacher.send(:extract_filename_from_url, url)
      
      expect(filename).to match(/image_\d+\.jpg/)
    end
  end

  describe 'error handling' do
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }

    context 'with partial failures' do
      let(:images_data) do
        [
          { blob: blob, alt: 'Good Image' },
          { alt: 'Bad Image' } # Missing source
        ]
      end

      it 'attaches valid images and reports errors' do
        expect do
          attacher.attach_to_product(product, images_data)
        end.to change { product.master.images.count }.by(1)

        expect(attacher.errors).to include(match(/No file, blob, or URL/i))
      end
    end

    context 'with exception during attachment' do
      let(:images_data) do
        [{ blob: blob, alt: 'Exception Image' }]
      end

      before do
        allow_any_instance_of(Spree::Image).to receive(:save).and_raise(StandardError.new('Unexpected error'))
      end

      it 'catches exception and returns error' do
        errors = attacher.attach_to_product(product, images_data)
        expect(errors).to include(match(/Unexpected error/i))
      end
    end
  end

  describe 'image indexing in error messages' do
    let(:images_data) do
      [
        { alt: 'Missing source 1' },
        { alt: 'Missing source 2' }
      ]
    end

    it 'includes image index in error messages' do
      errors = attacher.attach_to_product(product, images_data)
      
      expect(errors.first).to include('Image 1')
      expect(errors.second).to include('Image 2')
    end
  end

  describe 'resetting errors between calls' do
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.jpg') }

    it 'resets errors for each attach_to_product call' do
      # First call with error
      attacher.attach_to_product(product, [{ alt: 'No source' }])
      expect(attacher.errors).not_to be_empty

      # Second call with valid data
      attacher.attach_to_product(product, [{ blob: blob }])
      expect(attacher.errors).to be_empty
    end

    it 'resets errors for each attach_to_variant call' do
      # First call with error
      attacher.attach_to_variant(variant, [{ alt: 'No source' }])
      expect(attacher.errors).not_to be_empty

      # Second call with valid data
      attacher.attach_to_variant(variant, [{ blob: blob }])
      expect(attacher.errors).to be_empty
    end
  end
end
