module ProductImport
  # Service object for bulk updating products
  # Extracted from ProductImportFilesController#bulk_update
  class BulkUpdater
    attr_reader :update_count, :error_count, :errors

    def initialize(update_rows, current_ability)
      @update_rows = update_rows
      @current_ability = current_ability
      @update_count = 0
      @error_count = 0
      @errors = {}
    end

    # Executes the bulk update operation for all selected products
    # Iterates through update_rows and processes each selected product
    # Returns: self (for method chaining)
    def call
      @update_rows.each do |product_id, product_data|
        next unless selected?(product_data)

        product = find_product(product_id)
        next unless product

        update_product(product, product_data)
      end

      self
    end

    # Checks if the update was completely successful (no errors)
    # Returns: Boolean
    def success?
      @error_count.zero?
    end

    # Checks if the update had both successes and failures
    # Returns: Boolean
    def partial_success?
      @update_count.positive? && @error_count.positive?
    end

    # Generates an appropriate flash message hash based on results
    # Returns: Hash with :type (symbol) and :message (string) keys
    def flash_message
      if success?
        { type: :success, message: "Successfully updated #{@update_count} #{'product'.pluralize(@update_count)}." }
      elsif @update_count.zero?
        { type: :error, message: "Failed to update all products." }
      else
        { type: :warning, message: "Updated #{@update_count} #{'product'.pluralize(@update_count)}, but #{@error_count} #{'product'.pluralize(@error_count)} failed." }
      end
    end

    private

    # Checks if product is selected for update (checkbox ticked in UI)
    # Returns: Boolean
    def selected?(product_data)
      product_data[:_selected].to_s == '1'
    end

    # Finds product by ID, scoped by current user's abilities
    # Returns: Product or nil if not found/accessible
    def find_product(product_id)
      Spree::Product.accessible_by(@current_ability, :update).find_by(id: product_id)
    end

    # Updates a single product with provided data
    # Assigns basic attributes first, then processes complex associations
    # Tracks success/error counts for reporting
    def update_product(product, product_data)
      ActiveRecord::Base.transaction do
        assign_basic_attributes(product, product_data)
        product.save!
        process_product_updates(product, product_data)
      end

      @update_count += 1
    rescue ActiveRecord::RecordInvalid => e
      @error_count += 1
      @errors[product.id] = e.record.errors.full_messages
    rescue ActiveRecord::RecordNotSaved, StandardError => e
      @error_count += 1
      @errors[product.id] = [e.message]
    end

    # Assigns basic scalar attributes to product
    # Only updates fields that are present in the data
    # Handles optional vendor and detail attributes based on product's capabilities
    def assign_basic_attributes(product, data)
      product.name                 = data[:name]                if data[:name].present?
      product.sku                  = data[:sku]                 if data[:sku].present?
      product.available_on         = parse_available_on(data[:available_on]) if data.key?(:available_on)
      product.shipping_category_id = data[:shipping_category_id] if data[:shipping_category_id].present?
      product.price                = data[:master_price]        if data[:master_price].present?
      product.meta_title           = data[:meta_title]          if data.key?(:meta_title)
      product.meta_keywords        = data[:meta_keywords]       if data.key?(:meta_keywords)
      product.meta_description     = data[:meta_description]    if data.key?(:meta_description)

      # Optional attributes (depends on Spree extensions)
      product.vendor_id = data[:vendor_id] if data[:vendor_id].present? && product.respond_to?(:vendor_id=)
      product.detail    = data[:detail]    if data[:detail].present? && product.respond_to?(:detail=)
    end

    # Processes complex updates: taxons, variants, images, stock
    # Called after basic attributes are saved
    def process_product_updates(product, data)
      update_taxons(product, data)
      update_existing_variants(product, data)
      create_new_variants(product, data)
      create_new_images(product, data)
      update_stock_levels(product, data)
      update_prices(product, data)
    end

    # Updates product's taxon (category) associations
    # Replaces existing taxons with new selection
    def update_taxons(product, data)
      return unless data[:taxon_ids].present?

      taxon_ids = Array(data[:taxon_ids]).map(&:to_i).reject(&:zero?)
      product.taxons = Spree::Taxon.where(id: taxon_ids)
    end

    # Updates attributes of existing variants
    # Handles both regular variants and master variant
    def update_existing_variants(product, data)
      return unless data[:variants].present? && data[:variants].respond_to?(:each)

      data[:variants].each do |variant_id, variant_data|
        variant = find_variant(product, variant_id)
        next unless variant

        update_variant_attributes(variant, variant_data)
      end
    end

    # Finds a variant by ID, with special handling for master variant
    # Returns: Variant or nil if not found
    def find_variant(product, variant_id)
      product.variants.find_by(id: variant_id) || 
        (product.master.id.to_s == variant_id.to_s ? product.master : nil)
    end

    # Updates scalar attributes of a variant
    # Delegates price update to separate method
    def update_variant_attributes(variant, data)
      variant.sku        = data[:sku]        if data[:sku].present?
      variant.cost_price = data[:cost_price] if data[:cost_price].present?
      variant.weight     = data[:weight]     if data[:weight].present?

      update_variant_price(variant, data)
      variant.save
    end

    # Updates price and compare_at_price for a variant
    # Only updates fields that are present in data
    def update_variant_price(variant, data)
      return unless variant.default_price

      variant.default_price.amount            = data[:price]            if data[:price].present?
      variant.default_price.compare_at_amount = data[:compare_at_price] if data.key?(:compare_at_price)
      variant.default_price.save
    end

    # Creates new variants for the product using VariantBuilder
    # Collects any errors from variant creation
    def create_new_variants(product, data)
      return unless data[:new_variants].present? && data[:new_variants].respond_to?(:values)

      new_variants_array = data[:new_variants].values
      variant_builder = VariantBuilder.new(product)
      variant_errors = variant_builder.create_variants(new_variants_array)

      if variant_errors.any?
        @errors[product.id] ||= []
        @errors[product.id] << "Variant errors: #{variant_errors.join(', ')}"
      end
    end

    # Attaches new images to the product using ImageAttacher
    # Collects any errors from image attachment
    def create_new_images(product, data)
      return unless data[:new_images].present?

      images_data = data[:new_images].respond_to?(:values) ? data[:new_images].values : Array(data[:new_images])
      
      image_attacher = ImageAttacher.new
      image_errors = image_attacher.attach_to_product(product, images_data)

      if image_errors.any?
        @errors[product.id] ||= []
        @errors[product.id].concat(image_errors)
      end
    end

    # Updates stock levels for product variants.
    # Param structure: stock_items: { variant_id => { location_id => { count_on_hand, backorderable } } }
    # Note: keys may be Symbols (from deep_symbolize_keys), so .to_s is required for AR integer casts.
    def update_stock_levels(product, data)
      return unless data[:stock_items].present? && data[:stock_items].respond_to?(:each)

      data[:stock_items].each do |variant_id, locations|
        variant = find_variant(product, variant_id.to_s)
        next unless variant
        next unless locations.respond_to?(:each)

        locations.each do |location_id, stock_data|
          update_variant_stock(variant, location_id.to_s, stock_data)
        end
      end
    end

    # Sets count_on_hand and backorderable for a variant at a specific stock location.
    # Mirrors StockItemsController reference: set_up_stock_item + StockMovement for count,
    # direct attribute assignment + save for backorderable.
    def update_variant_stock(variant, location_id, stock_data)
      stock_location = Spree::StockLocation.find_by(id: location_id)
      return unless stock_location

      # Use Spree's native find-or-create (matches reference: set_up_stock_item)
      stock_item = stock_location.set_up_stock_item(variant)

      # Adjust count via StockMovement delta (matches StockItemsController#create reference)
      new_count = stock_data[:count_on_hand].to_i
      delta = new_count - stock_item.count_on_hand.to_i
      if delta != 0
        movement = stock_location.stock_movements.build(quantity: delta)
        movement.stock_item = stock_item
        movement.save
      end

      # Update backorderable directly (matches StockItemsController#update + determine_backorderable)
      stock_item.backorderable = stock_data[:backorderable].to_s == '1'
      stock_item.save
    end

    # Updates prices for product variants.
    # Param structure: prices: { variant_id => { price, compare_price, currency } }
    def update_prices(product, data)
      return unless data[:prices].present? && data[:prices].respond_to?(:each)

      data[:prices].each do |variant_id, price_data|
        variant = find_variant(product, variant_id.to_s)
        next unless variant

        currency = price_data[:currency].presence || Spree::Config[:currency]
        price = variant.prices.find_or_initialize_by(currency: currency)
        price.amount            = price_data[:price]         if price_data[:price].present?
        price.compare_at_amount = price_data[:compare_price] if price_data.key?(:compare_price)
        price.save if price.changed?
      end
    end

    # Parses available_on date string into Time object
    # Returns: Time or nil if parsing fails
    def parse_available_on(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
