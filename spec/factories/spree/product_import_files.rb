FactoryBot.define do
  # Base factory for ProductImportFile
  factory :product_import_file, class: Spree::ProductImportFile do
    name { "Product Import #{FFaker::Lorem.word}" }
    import_type { :file_import }
    status { :active }
    user { nil }
    row_data { [] }
    total_rows { 0 }
    processed_rows { 0 }
    success_count { 0 }
    failure_count { 0 }
    
    # Automatically attach a file for file imports
    after(:build) do |import_file|
      if import_file.file_import?
        file_name = File.expand_path("../../../support/data/product_import_ok.xlsx", __FILE__)
        mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        import_file.file.attach(
          io: File.open(file_name),
          filename: 'product_import.xlsx',
          content_type: mime_type
        )
      end
    end
    
    # Trait for manual import type
    trait :manual_import do
      import_type { :manual_import }
      row_data { [{ name: 'Test Product', sku: 'TEST-001' }] }
    end
    
    # Trait with processing status
    trait :processing do
      status { :processing }
    end
    
    # Trait with success status
    trait :success do
      status { :success }
    end
    
    # Trait with failed status
    trait :failed do
      status { :failed }
    end
  end

  # Factory for successful file imports
  factory :product_import_file_ok, parent: :product_import_file do
    name { FFaker::Name.name }
    import_type { :file_import }
    
    after(:build) do |import_file|
      file_name = File.expand_path("../../../support/data/product_import_ok.xlsx", __FILE__)
      mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      import_file.file.attach(
        io: File.open(file_name),
        filename: 'product_import_ok.xlsx',
        content_type: mime_type
      )
    end
  end

  # Factory for file imports with errors
  factory :product_import_file_error, parent: :product_import_file do
    name { FFaker::Name.name }
    import_type { :file_import }
    
    after(:build) do |import_file|
      file_name = File.expand_path("../../../support/data/product_import_error.xlsx", __FILE__)
      mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      import_file.file.attach(
        io: File.open(file_name),
        filename: 'product_import_error.xlsx',
        content_type: mime_type
      )
    end
  end
end
