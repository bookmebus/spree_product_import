Spree::Core::Engine.add_routes do
  # Add your extension routes here
  namespace :admin do
    resources :product_import_files
  end

end
