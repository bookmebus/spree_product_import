require 'open-uri'
require 'ipaddr'
require 'socket'

module ProductImport
  # Service object for attaching images to products and variants
  # Handles both URL-based and file upload images
  class ImageAttacher
    attr_reader :errors

    def initialize
      @errors = []
    end

    # Attaches multiple images to a product's master variant
    # Handles URL-based images and file uploads
    # Returns: Array of error message strings
    def attach_to_product(product, images_data)
      @errors = []
      
      return @errors if images_data.blank?

      images_array = normalize_images_data(images_data)
      
      images_array.each_with_index do |image_data, index|
        attach_image(product.master, image_data, index)
      end

      @errors
    end

    # Attaches multiple images to a specific variant
    # Handles URL-based images and file uploads
    # Returns: Array of error message strings
    def attach_to_variant(variant, images_data)
      @errors = []
      
      return @errors if images_data.blank?

      images_array = normalize_images_data(images_data)
      
      images_array.each_with_index do |image_data, index|
        attach_image(variant, image_data, index)
      end

      @errors
    end

    private

    # Converts images_data from hash or parameters to array
    # Returns: Array of image data hashes
    def normalize_images_data(images_data)
      if images_data.is_a?(Hash) || images_data.is_a?(ActionController::Parameters)
        images_data.values
      else
        Array(images_data)
      end
    end

    # Attaches a single image to a viewable (product or variant)
    # Determines attachment method: blob, file upload, or URL
    def attach_image(viewable, image_data, index)
      data_hash = normalize_image_data(image_data)
      
      file = extract_file(data_hash)
      blob = extract_blob(data_hash)
      url = extract_url(data_hash)
      alt_text = extract_alt_text(data_hash)

      if blob.present?
        attach_from_blob(viewable, blob, alt_text, index)
      elsif file.present?
        attach_from_upload(viewable, file, alt_text, index)
      elsif url.present?
        attach_from_url(viewable, url, alt_text, index)
      else
        @errors << "Image #{index + 1}: No file, blob, or URL provided"
      end
    end

    # Attaches an image from an existing ActiveStorage blob
    # Most efficient method - reuses blob without duplication
    def attach_from_blob(viewable, blob, alt_text, index)
      # Attach existing blob directly (more efficient - reuses blob without duplication)
      image = Spree::Image.new(viewable: viewable, alt: alt_text)
      image.attachment.attach(blob)

      unless image.save
        @errors << "Image #{index + 1}: #{image.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      @errors << "Image #{index + 1}: #{e.message}"
    end

    # Attaches an image from an uploaded file
    def attach_from_upload(viewable, file, alt_text, index)
      image = Spree::Image.new(viewable: viewable, alt: alt_text)
      image.attachment.attach(file)

      unless image.save
        @errors << "Image #{index + 1}: #{image.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      @errors << "Image #{index + 1}: #{e.message}"
    end

    # Downloads and attaches an image from a URL
    # Handles HTTP errors and network issues
    def attach_from_url(viewable, url, alt_text, index)
      begin
        uri = URI.parse(url)

        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          @errors << "Image #{index + 1}: URL must use http or https scheme"
          return
        end

        unless uri.host.present?
          @errors << "Image #{index + 1}: URL is missing a host"
          return
        end

        # Block private/loopback addresses to prevent SSRF
        begin
          resolved = IPSocket.getaddress(uri.host)
          addr = IPAddr.new(resolved)
          if addr.loopback? || addr.private? || addr.link_local?
            @errors << "Image #{index + 1}: URL resolves to a private or reserved address"
            return
          end
        rescue SocketError
          @errors << "Image #{index + 1}: Could not resolve host '#{uri.host}'"
          return
        end

        io = uri.open
        filename = extract_filename_from_url(url)
        
        image = Spree::Image.new(viewable: viewable, alt: alt_text)
        image.attachment.attach(io: io, filename: filename)

        unless image.save
          @errors << "Image #{index + 1}: #{image.errors.full_messages.join(', ')}"
        end
      rescue OpenURI::HTTPError => e
        @errors << "Image #{index + 1}: Failed to download from URL - #{e.message}"
      rescue StandardError => e
        @errors << "Image #{index + 1}: #{e.message}"
      end
    end

    # Normalizes image data to hash with symbolized keys
    # Returns: Hash
    def normalize_image_data(image_data)
      if image_data.is_a?(ActionController::Parameters)
        image_data.to_unsafe_h.deep_symbolize_keys
      elsif image_data.is_a?(Hash)
        image_data.deep_symbolize_keys
      else
        { file: image_data }
      end
    end

    # Extracts file from image data (various key names supported)
    def extract_file(data)
      data[:file] || data[:attachment] || data[:image]
    end

    # Extracts ActiveStorage blob from image data
    def extract_blob(data)
      data[:blob]
    end

    # Extracts URL from image data (various key names supported)
    def extract_url(data)
      data[:url] || data[:image_url] || data[:src]
    end

    # Extracts alt text from image data
    def extract_alt_text(data)
      data[:alt] || data[:alt_text] || ''
    end

    # Extracts filename from URL path
    # Falls back to timestamped filename if parsing fails
    def extract_filename_from_url(url)
      uri = URI.parse(url)
      filename = File.basename(uri.path.to_s)
      return "image_#{Time.current.to_i}.jpg" if filename.blank? || filename == '.' || filename == '/' || !filename.include?('.')

      filename
    rescue StandardError
      "image_#{Time.current.to_i}.jpg"
    end
  end
end
