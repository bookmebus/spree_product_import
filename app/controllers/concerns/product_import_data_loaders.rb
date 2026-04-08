# Concern for loading common data needed in ProductImportFilesController
# Extracted data loading methods to reduce controller bloat
module ProductImportDataLoaders
  extend ActiveSupport::Concern

  included do
    # before_action :load_products, only: :index
    before_action :load_shipping_categories, only: %i[new create bulk_update]
    # before_action :load_stock_locations, only: %i[new bulk_update]
    # before_action :load_option_types, only: %i[new create]
  end

  private

  # Loads paginated products for the index page
  # Uses current_ability to scope accessible products
  def load_products
    @products = Spree::Product
      .accessible_by(current_ability, :index)
      .order(created_at: :desc)
      .page(params[:products_page])
      .per(products_per_page)
  end

  # Loads all shipping categories for product import dropdowns
  def load_shipping_categories
    @shipping_categories = Spree::ShippingCategory.order(:name)
  end

  # Loads stock locations for inventory management
  # In update mode, filters by selected vendor to show only relevant locations
  # In create mode, shows all stock locations
  def load_stock_locations
    # In update mode, filter stock locations by the selected vendor
    if params[:mode] == 'update' && params[:update_vendor_id].present?
      vendor_id = params[:update_vendor_id]
      @stock_locations = Spree::StockLocation.where(vendor_id: vendor_id).order(:name)
    else
      @stock_locations = Spree::StockLocation.active.order(:name)
    end
  end

  # Loads option types with their option values for variant creation
  # Ordered by position and name for consistent display
  def load_option_types
    option_value_includes = Spree::OptionValue.reflect_on_association(:translations) ? { option_values: :translations } : :option_values
    option_type_includes = Spree::OptionType.reflect_on_association(:translations) ? [:translations, option_value_includes] : [option_value_includes]
    @option_types = Spree::OptionType
      .includes(*option_type_includes)
      .order(:position, :name)
  end

  # Loads products for bulk update mode
  # Supports two filtering modes:
  # 1. Vendor-only mode: Filter by vendor_id
  # 2. Search mode: Use ransack to search by name or SKU
  #
  # Eager loads all associations needed for the update form to prevent N+1 queries
  # Includes master variant, variants, option values, prices, images, stock items, etc.
  def load_update_products
    @update_vendor_id = params[:update_vendor_id].presence
    @update_per_page  = [(params[:update_per_page].presence&.to_i || 25), 100].min

    # Check if search parameters are present (name or SKU)
    @update_search_active = params[:q].present? &&
      (params[:q][:name_cont].present? || params[:q][:sku_cont].present? || params[:q][:variants_including_master_sku_cont].present?)

    # Return early if neither vendor nor search is active
    return unless @update_vendor_id.present? || @update_search_active

    # Cache currency once so the view doesn't call Spree::Config[:currency] per product
    @default_price_currency = Spree::Config[:currency]

    # Build product-level includes: add Globalize translations and ActionText rich text
    # only when those associations actually exist (absent in the test dummy app).
    product_includes = [:taxons, :vendor, :shipping_category]
    product_includes << :translations   if Spree::Product.reflect_on_association(:translations)
    product_includes << :rich_text_detail if Spree::Product.reflect_on_association(:rich_text_detail)

    # Eager-load ActiveStorage attachments+blobs for images when available.
    images_eager = Spree::Image.reflect_on_association(:attachment_attachment) \
      ? { images: { attachment_attachment: :blob } } \
      : :images

    # Eager-load option_type (needed for options_text) plus its translations.
    option_type_sub = Spree::OptionType.reflect_on_association(:translations) \
      ? { option_type: :translations } : :option_type
    ov_nested = [option_type_sub]
    ov_nested << :translations if Spree::OptionValue.reflect_on_association(:translations)

    scope = Spree::Product
      .accessible_by(current_ability, :update)
      .includes(
        *product_includes,
        master: [
          :prices,
          images_eager,
          { option_values: ov_nested },
          stock_items: :stock_location
        ],
        variants: [
          { option_values: ov_nested },
          :prices,
          images_eager,
          stock_items: :stock_location
        ]
      )

    # Apply vendor filter if using vendor-only mode
    if @update_vendor_id.present? && !@update_search_active
      scope = scope.where(vendor_id: @update_vendor_id) if defined?(Spree::Vendor)
      @update_q = scope.ransack
    elsif @update_search_active
      search_params = params[:q].to_unsafe_h
      search_params[:deleted_at_null] ||= '1'
      search_params[:not_discontinued] ||= '1'
      @update_q = scope.ransack(search_params)
    end

    @update_products = @update_q.result.page(params[:update_page]).per(@update_per_page)
  end

  # Validates and returns per-page limit for products pagination
  # Enforces minimum of 25 and maximum of 200 products per page
  # Returns: Integer between 25 and 200
  def products_per_page
    per_page = params[:products_per_page].to_i
    return 25 if per_page <= 0
    return 200 if per_page > 200

    per_page
  end

  # Validates and returns per-page limit for vendors pagination
  # Enforces minimum of 25 and maximum of 200 vendors per page
  # Returns: Integer between 25 and 200
  def vendors_per_page
    per_page = params[:vendors_per_page].to_i
    return 25 if per_page <= 0
    return 200 if per_page > 200

    per_page
  end
end
