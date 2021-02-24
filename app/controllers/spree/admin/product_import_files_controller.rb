module Spree
  module Admin
    class ProductImportFilesController < ResourceController

      def index
        # load_resource
      end

      def new
        @product_import_file = Spree::ProductImportFile.new
      end

      def create
        @product_import = Spree::ProductImportFile.new(filter_parames)
        @product_import.file_name = filter_parames[:file].original_filename
        @product_import.user_id = spree_current_user.id
        @product_import.save

        # CreateProductsFromCsvJob.perform_later(@product_import)

        redirect_to admin_product_import_files_path
      end

      private
      def filter_parames
        params.require(:product_import_file).permit(:name, :file)
      end

      def collection
        return @collection if @collection.present?

        params[:q] ||= {}
        params[:q][:status] ||= '0'

        params[:q][:s] ||= 'name asc'
        @collection = super
        # Don't delete params[:q][:deleted_at_null] here because it is used in view to check the
        # checkbox for 'q[deleted_at_null]'. This also messed with pagination when deleted_at_null is checked.
        if params[:q][:deleted_at_null] == '0'
          @collection = @collection.with_deleted
        end
        # @search needs to be defined as this is passed to search_form_for
        # Temporarily remove params[:q][:deleted_at_null] from params[:q] to ransack products.
        # This is to include all products and not just deleted products.
        @search = @collection.ransack(params[:q].reject { |k, _v| k.to_s == 'deleted_at_null' })
        @collection = @search.result.
                      page(params[:page]).
                      per(params[:per_page])
        @collection
      end
    end
  end
end
