module ProductImport
  # Service object for creating product variants with option values
  # Extracted from ProductImportFilesController#create_variants_for_product
  class VariantBuilder
    attr_reader :errors

    def initialize(product)
      @product = product
      @errors = []
    end

    # Creates multiple variants for a product from variants_data array
    # Validates SKUs first, then prepares option types, then creates variants
    # Returns: Array of error messages (empty if all successful)
    def create_variants(variants_data)
      return [] if variants_data.blank? || !variants_data.is_a?(Array)

      # Validate SKUs before creating variants
      sku_errors = validate_variant_skus(variants_data)
      if sku_errors.any?
        @errors.concat(sku_errors)
        return @errors
      end

      prepare_option_types(variants_data)
      create_variant_records(variants_data)

      @errors
    end

    private

    # Validates that variant SKUs don't conflict with master or each other
    # Checks:
    # - Variant SKU doesn't match master product SKU
    # - No duplicate SKUs among variants
    # Returns: Array of error message strings
    def validate_variant_skus(variants_data)
      errors = []
      master_sku = @product.sku&.downcase
      variant_skus = Set.new

      variants_data.each_with_index do |variant_data, index|
        next unless valid_variant_data?(variant_data)

        data_hash = normalize_variant_data(variant_data)
        variant_sku = (data_hash[:sku] || data_hash['sku'])&.strip

        if variant_sku.blank?
          errors << "Variant #{index + 1}: SKU can't be blank"
          next
        end

        variant_sku_lower = variant_sku.downcase

        # Check if variant SKU matches master product SKU
        if master_sku.present? && variant_sku_lower == master_sku
          errors << "Variant #{index + 1}: SKU '#{variant_sku}' conflicts with master product SKU"
        end

        # Check for duplicate SKUs among variants
        if variant_skus.include?(variant_sku_lower)
          errors << "Variant #{index + 1}: SKU '#{variant_sku}' is duplicated within variants"
        else
          variant_skus.add(variant_sku_lower)
        end
      end

      errors
    end

    # Prepares the product by adding any missing option types
    # Collects option types from all variant data, then adds them to product
    def prepare_option_types(variants_data)
      option_types_to_add = collect_option_types(variants_data)
      add_option_types_to_product(option_types_to_add)
    end

    # Collects all unique option types needed from variants_data
    # Only includes option types not already on the product
    # Returns: Array of OptionType objects
    def collect_option_types(variants_data)
      option_values_by_id = preload_option_values(variants_data)
      option_types = Set.new

      variants_data.each do |variant_data|
        next unless valid_variant_data?(variant_data)

        option_values_hash = extract_option_values_hash(variant_data)
        next if option_values_hash.empty?

        option_values_hash.each do |_option_type_id, option_value_id|
          option_value = option_values_by_id[option_value_id.to_i]
          next unless option_value

          option_types << option_value.option_type unless @product.option_types.include?(option_value.option_type)
        end
      end

      option_types.to_a
    end

    # Adds option types to the product and saves
    # Returns: Boolean (true if successful, false if save failed)
    def add_option_types_to_product(option_types)
      return if option_types.empty?

      option_types.each do |option_type|
        @product.option_types << option_type
      end

      unless @product.save
        @errors << "Failed to add option types to product: #{@product.errors.full_messages.join(', ')}"
        return false
      end

      @product.reload
      true
    end

    # Creates variant records from variants_data
    # Preloads option values once, then creates each variant
    def create_variant_records(variants_data)
      option_values_by_id = preload_option_values(variants_data)

      variants_data.each_with_index do |variant_data, index|
        next unless valid_variant_data?(variant_data)

        create_single_variant(variant_data, index, option_values_by_id)
      end
    end

    # Creates a single variant with its option values and price
    # 
    # @param variant_data [Hash] Variant attributes and option values
    # @param index [Integer] Variant index for error reporting
    # @param option_values_by_id [Hash] Preloaded option values by ID
    def create_single_variant(variant_data, index, option_values_by_id)
      data_hash = normalize_variant_data(variant_data)
      option_values_hash = extract_option_values_hash(variant_data)
      
      return if option_values_hash.empty?

      option_values = build_option_values(option_values_hash, option_values_by_id)
      return if option_values.empty?

      variant = build_variant(data_hash)
      variant.option_values = option_values

      save_variant_with_price(variant, data_hash, index)
    end

    # Builds a new variant instance (not yet saved)
    # Sets default tax_category_id to product's if not provided
    # Returns: Unsaved Variant instance
    def build_variant(data)
      @product.variants.new(
        sku: data[:sku] || data['sku'],
        cost_price: data[:cost_price] || data['cost_price'],
        weight: data[:weight] || data['weight'],
        height: data[:height] || data['height'],
        width: data[:width] || data['width'],
        depth: data[:depth] || data['depth'],
        tax_category_id: data[:tax_category_id] || data['tax_category_id'] || @product.tax_category_id,
        track_inventory: true
      )
    end

    # Saves variant and creates its price record
    # Records any validation errors
    def save_variant_with_price(variant, data, index)
      if variant.save
        create_variant_price(variant, data, index)
      else
        @errors << "Variant #{index + 1}: #{variant.errors.full_messages.join(', ')}"
      end
    end

    # Creates or updates the price record for the variant
    # Includes price and optional compare_at_price
    # Uses store's default currency
    def create_variant_price(variant, data, index)
      price = data[:price] || data['price']
      compare_at_price = data[:compare_at_price] || data['compare_at_price']

      return unless price

      currency = Spree::Config[:currency]
      
      # Find existing price or create new one
      variant_price = variant.prices.find_or_initialize_by(currency: currency)
      variant_price.amount = price
      variant_price.compare_at_amount = compare_at_price if compare_at_price

      unless variant_price.save
        @errors << "Variant #{index + 1} price: #{variant_price.errors.full_messages.join(', ')}"
      end
    end

    # Preloads all option values referenced in variants_data
    # Returns: Hash of OptionValue objects indexed by ID
    def preload_option_values(variants_data)
      all_option_value_ids = []

      variants_data.each do |variant_data|
        next unless valid_variant_data?(variant_data)

        option_values_hash = extract_option_values_hash(variant_data)
        all_option_value_ids.concat(option_values_hash.values.map(&:to_i))
      end

      Spree::OptionValue
        .includes(:option_type)
        .where(id: all_option_value_ids.uniq)
        .index_by(&:id)
    end

    # Builds array of OptionValue objects from option_values_hash
    # Filters out any IDs that don't exist in option_values_by_id
    # Returns: Array of OptionValue objects
    def build_option_values(option_values_hash, option_values_by_id)
      option_values = []

      option_values_hash.each do |_option_type_id, option_value_id|
        option_value = option_values_by_id[option_value_id.to_i]
        option_values << option_value if option_value
      end

      option_values
    end

    # Checks if variant_data is a valid hash-like structure
    # Returns: Boolean
    def valid_variant_data?(variant_data)
      variant_data.is_a?(Hash) || variant_data.is_a?(ActionController::Parameters)
    end

    # Converts ActionController::Parameters to hash with symbolized keys
    # Returns: Hash
    def normalize_variant_data(variant_data)
      if variant_data.is_a?(ActionController::Parameters)
        variant_data.to_unsafe_h.deep_symbolize_keys
      else
        variant_data
      end
    end

    # Extracts option_values hash from variant data
    # Handles both symbol and string keys, Parameters and Hash
    # Returns: Hash of option_type_id => option_value_id
    def extract_option_values_hash(variant_data)
      data_hash = normalize_variant_data(variant_data)
      option_values = data_hash[:option_values] || data_hash['option_values'] || {}

      if option_values.is_a?(ActionController::Parameters)
        option_values.to_unsafe_h
      else
        option_values
      end
    end

    # Generates a SKU by appending option value names to product SKU/slug
    # Example: "SHIRT-RED-LARGE"
    # Returns: String SKU
    def generate_sku(option_values)
      base_sku = @product.sku.presence || @product.slug.parameterize
      option_suffix = option_values.map { |ov| ov.name.parameterize }.join('-')
      "#{base_sku}-#{option_suffix}"
    end
  end
end
