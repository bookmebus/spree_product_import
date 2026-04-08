module ProductImport
  # Service object for creating products from manual form rows
  # Extracted from ProductImportFilesController#create_products_from_rows
  class RowCreator
    attr_reader :errors, :success_count, :failures, :warnings, :successes

    def initialize(rows, current_user, product_import_file = nil)
      @rows = rows
      @current_user = current_user
      @product_import_file = product_import_file
      @failures = []
      @warnings = []
      @successes = []
      @success_count = 0
      @errors = {}
      @existing_skus = nil
      @existing_slugs = nil
      @shipping_categories = nil
    end

    # Executes the product creation from all rows
    # Preloads validation data for performance, then processes each row
    # Updates progress after each row if product_import_file is present
    # Returns: self (for method chaining)
    def call
      preload_validation_data
      
      @rows.each_with_index do |row, index|
        create_product_from_row(row, index)
        update_progress(index + 1) if @product_import_file
      end

      self
    end

    # Checks if all products were created successfully (no failures)
    # Note: Warnings (e.g., image upload failures) don't count as failures
    # Returns: Boolean
    def success?
      @failures.empty?
    end

    private

    # Updates the ProductImportFile progress columns
    # Called after each row is processed to provide real-time progress
    def update_progress(processed_count)
      @product_import_file.update_columns(
        processed_rows: processed_count,
        success_count: @success_count,
        failure_count: @failures.count
      )
    end

    # Preloads all validation data before processing rows
    # Prevents N+1 queries and enables batch validation
    def preload_validation_data
      preload_existing_skus
      preload_existing_slugs
      preload_shipping_categories
    end

    # Loads all existing SKUs from database into a Set for fast lookups
    # Used to validate SKU uniqueness before attempting to save
    def preload_existing_skus
      skus = @rows.map { |row| row[:sku] }.compact.reject(&:blank?)
      
      if skus.empty?
        @existing_skus = Set.new
        return
      end

      @existing_skus = Spree::Variant
        .where('LOWER(sku) IN (?)', skus.map(&:downcase))
        .where(deleted_at: nil)
        .pluck('LOWER(sku)')
        .to_set
    end

    # Loads all existing product slugs from database into a Set
    # Pre-generates potential slugs from row names for validation
    # Prevents slug conflicts before attempting to save
    def preload_existing_slugs
      names = @rows.map { |row| row[:name] }.compact.reject(&:blank?)
      
      if names.empty?
        @existing_slugs = Set.new
        return
      end

      potential_slugs = names.map { |name| name.parameterize }

      @existing_slugs = existing_slug_relation
        .where('LOWER(slug) IN (?)', potential_slugs.map(&:downcase))
        .pluck('LOWER(slug)')
        .to_set
    end

    # Loads shipping categories into a hash indexed by ID
    # Avoids database queries during row processing
    def preload_shipping_categories
      category_ids = @rows.map { |row| row[:shipping_category_id] }.compact.reject(&:blank?).uniq
      
      if category_ids.empty?
        @shipping_categories = {}
        return
      end

      @shipping_categories = Spree::ShippingCategory
        .where(id: category_ids)
        .index_by(&:id)
    end

    # Creates a product from a single row of data
    # Pre-validates the row before attempting to save
    # If product creation succeeds, processes associations (variants, images, taxons)
    # Reindexes product for search if searchkick is enabled
    # 
    # @param row [Hash] Product data with symbolized keys
    # @param index [Integer] Row index (0-based) for error reporting
    def create_product_from_row(row, index)
      # Pre-validate before attempting to save
      validation_errors = validate_row(row, index)
      if validation_errors.any?
        @failures << {
          index: index + 1,
          name: row[:name],
          sku: row[:sku],
          price: row[:master_price],
          is_master: true,
          errors: validation_errors
        }
        return
      end

      product = build_product(row)

      if product.save
        process_product_associations(product, row)
        
        # Reindex for search (if searchkick is enabled)
        # In searchkick 4.x, single record reindex is synchronous by default
        product.reindex if product.respond_to?(:reindex)
        
        @successes << {
          product_id: product.id,
          slug: product.slug,
          name: row[:name],
          sku: row[:sku],
          price: row[:master_price],
          is_master: true
        }
        @success_count += 1
      else
        @failures << {
          index: index + 1,
          name: row[:name],
          sku: row[:sku],
          price: row[:master_price],
          is_master: true,
          errors: product.errors.full_messages
        }
      end
    end

    # Validates a row before attempting to create the product
    # Checks:
    # - SKU uniqueness (against DB and within batch)
    # - Slug uniqueness (against DB and within batch)
    # - Shipping category existence
    # - Variant SKU conflicts
    # 
    # Adds validated SKUs/slugs to tracking sets to prevent duplicates within batch
    # Returns: Array of error message strings
    def validate_row(row, index)
      errors = []

      # Validate SKU uniqueness against existing SKUs
      if row[:sku].present? && @existing_skus.include?(row[:sku].downcase)
        errors << "SKU has already been taken"
      end

      # Validate slug uniqueness against existing slugs
      potential_slug = row[:name]&.parameterize
      if potential_slug.present? && @existing_slugs.include?(potential_slug.downcase)
        errors << "Name generates a slug that already exists"
      end

      # Validate shipping category exists
      if row[:shipping_category_id].present?
        unless shipping_category_exists?(row[:shipping_category_id])
          errors << "Shipping category not found"
        end
      end

      # Validate variant SKUs don't conflict with master SKU
      if row[:variants].present? && row[:sku].present?
        variant_sku_errors = validate_variant_skus_in_row(row)
        errors.concat(variant_sku_errors)
      end

      # Track new SKUs to prevent duplicates within the same batch
      if row[:sku].present? && errors.empty?
        sku_lower = row[:sku].downcase
        unless @existing_skus.add?(sku_lower)
          errors << "Duplicate SKU within batch"
        end
      end

      # Track new slugs to prevent duplicates within the same batch
      if potential_slug.present? && errors.empty?
        slug_lower = potential_slug.downcase
        unless @existing_slugs.add?(slug_lower)
          errors << "Duplicate name/slug within batch"
        end
      end

      errors
    end

    # Validates that variant SKUs don't conflict with master SKU or each other
    # Returns: Array of error message strings
    def validate_variant_skus_in_row(row)
      errors = []
      master_sku = row[:sku]&.strip&.downcase
      return errors if master_sku.blank?

      variants = row[:variants]
      return errors unless variants.is_a?(Array)

      variant_skus = Set.new

      variants.each_with_index do |variant_data, idx|
        next unless variant_data.is_a?(Hash) || variant_data.is_a?(ActionController::Parameters)

        variant_sku = (variant_data[:sku] || variant_data['sku'])&.strip
        next if variant_sku.blank?

        variant_sku_lower = variant_sku.downcase

        # Check if variant SKU matches master product SKU
        if variant_sku_lower == master_sku
          errors << "Variant #{idx + 1}: SKU '#{variant_sku}' conflicts with master product SKU"
        end

        # Check for duplicate SKUs among variants
        if variant_skus.include?(variant_sku_lower)
          errors << "Variant #{idx + 1}: SKU '#{variant_sku}' is duplicated within variants"
        else
          variant_skus.add(variant_sku_lower)
        end
      end

      errors
    end

    # Builds a new Product instance from row data
    # Uses preloaded shipping categories to avoid queries
    # Handles optional vendor and SEO attributes
    # Returns: Unsaved Product instance
    def build_product(row)
      product = Spree::Product.new
      product.name = row[:name]
      
      # Use preloaded shipping category to avoid query
      if row[:shipping_category_id].present?
        product.shipping_category = @shipping_categories[row[:shipping_category_id].to_i]
      end
      
      product.available_on = parse_available_on(row[:available_on])
      product.prototype_id = row[:prototype_id] if row[:prototype_id].present?
      product.price = row[:master_price]
      product.sku = row[:sku]
      product.detail = row[:detail] if row[:detail].present?
      product.meta_title = row[:meta_title] if row[:meta_title].present?
      product.meta_keywords = row[:meta_keywords] if row[:meta_keywords].present?
      product.meta_description = row[:meta_description] if row[:meta_description].present?

      if product.respond_to?(:vendor_id=)
        product.vendor_id = row[:vendor_id]
      end

      product
    end

    # Processes product associations after successful product save
    # Handles taxons, variants, and images
    # Errors in associations are recorded as warnings, not failures
    def process_product_associations(product, row)
      assign_taxons(product, row)
      create_variants(product, row)
      attach_images(product, row)
    end

    # Assigns taxons (categories) to the product
    # Converts taxon_ids to integers and filters out zeros
    def assign_taxons(product, row)
      return unless row[:taxon_ids].present?

      taxon_ids = Array(row[:taxon_ids]).map(&:to_i).reject(&:zero?)
      product.taxons = Spree::Taxon.where(id: taxon_ids) if taxon_ids.any?
    end

    # Creates variants for the product using VariantBuilder
    # Records any errors as warnings since product was created successfully
    def create_variants(product, row)
      return unless row[:variants].present?

      variant_builder = VariantBuilder.new(product)
      variant_errors = variant_builder.create_variants(row[:variants])
      
      if variant_errors.any?
        # Store as warning since product was created successfully
        @warnings << { 
          product_id: product.id, 
          errors: variant_errors 
        }
      end
    end

    # Attaches images to the product using ImageAttacher
    # Records any errors as warnings since product was created successfully
    def attach_images(product, row)
      return unless row[:images].present?

      image_attacher = ImageAttacher.new
      image_errors = image_attacher.attach_to_product(product, row[:images])
      
      if image_errors.any?
        # Store as warning since product was created successfully
        @warnings << { 
          product_id: product.id, 
          errors: image_errors 
        }
      end
    end

    # Parses available_on date string into Time object
    # Returns: Time or nil if parsing fails or input is blank
    def parse_available_on(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      nil
    end

    # Uses translation table when available (spree_globalize), otherwise products table.
    def existing_slug_relation
      translation_class = Spree::Product.respond_to?(:translation_class) ? Spree::Product.translation_class : nil

      if translation_class && translation_class.column_names.include?('slug')
        scope = translation_class.where(locale: I18n.locale)
        scope = scope.where(deleted_at: nil) if translation_class.column_names.include?('deleted_at')
        scope
      else
        scope = Spree::Product.all
        scope = scope.where(deleted_at: nil) if Spree::Product.column_names.include?('deleted_at')
        scope
      end
    end

    def shipping_category_exists?(shipping_category_id)
      id = shipping_category_id.to_i
      return false if id.zero?

      return true if @shipping_categories&.key?(id)

      Spree::ShippingCategory.where(id: id).exists?
    end
  end
end
