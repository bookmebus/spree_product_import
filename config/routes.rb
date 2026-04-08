Spree::Core::Engine.add_routes do
  # Add your extension routes here
  namespace :admin do
    resources :product_import_files do
      collection do
        patch :bulk_update
        get :vendors,         defaults: { format: :json }
        get :option_types,    defaults: { format: :json }
        get :stock_locations, defaults: { format: :json }
      end
    end
  end

end
