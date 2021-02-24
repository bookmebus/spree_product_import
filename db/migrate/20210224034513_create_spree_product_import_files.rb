class CreateSpreeProductImportFiles < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_product_import_files do |t|
      t.string :name
      t.string :file_name
      t.integer :status, default: 0
      t.string :error
      t.integer :user_id
      t.datetime :deleted_at

      t.timestamps
    end
  end
end
