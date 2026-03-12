FactoryBot.define do
  # Factory for option type with pre-created option values
  factory :option_type_with_values, parent: :option_type do
    name { FFaker::Product.brand }
    presentation { name }

    after(:create) do |option_type|
      # Create 3 option values for this option type
      create_list(:option_value, 3, option_type: option_type)
    end
  end
end
