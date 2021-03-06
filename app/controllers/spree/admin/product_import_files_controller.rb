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
        options = filter_params
        options[:user_id] = spree_current_user.id

        creator = ProductImport::Creator.new(options)
        creator.call

        if(creator.success?)
          flash.notice = Spree.t('success')
          redirect_to admin_product_import_files_path
        else
          flash.now[:error] = Spree.t('error')
          @product_import_file = creator.product_import_file
          render :new
        end
      end

      def show
        @product_import_file = Spree::ProductImportFile.find(params[:id])
      end

      def delete
        @product_import_file = Spree::ProductImportFile.find(params[:id])
        if @product_import_file.enqueued?
          @product_import_file.status = :cancelled
          @product_import_file.save
          flaush.notice = Spree.t("delete")
        end

        redirect_to :index
      end

      private
      def filter_params
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
