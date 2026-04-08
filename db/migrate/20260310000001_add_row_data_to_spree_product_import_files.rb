class AddRowDataToSpreeProductImportFiles < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_product_import_files, :row_data, :text
    add_column :spree_product_import_files, :import_type, :integer, default: 0
    add_column :spree_product_import_files, :total_rows, :integer, default: 0
    add_column :spree_product_import_files, :processed_rows, :integer, default: 0
    add_column :spree_product_import_files, :success_count, :integer, default: 0
    add_column :spree_product_import_files, :failure_count, :integer, default: 0
  end
end
