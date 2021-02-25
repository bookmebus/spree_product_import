FactoryBot.define do
  factory :product_import_file, class: Spree::ProductImportFile do
    name { FFaker::Name.name }
    file do 
      file_name = File.expand_path("../../../support/data/product_import.xlsx", __FILE__)
      mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      Rack::Test::UploadedFile.new(file_name, mime_type)
    end
  end
end
