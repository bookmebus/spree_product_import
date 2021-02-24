Deface::Override.new(
  virtual_path: 'spree/admin/shared/_main_menu',
  name: 'product_imports_sidebar_menu',
  insert_bottom: 'nav',
  partial: 'spree/admin/shared/main_menu_product_import',
)