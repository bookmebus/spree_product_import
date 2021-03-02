FactoryBot.define do
  factory :vendor_x, class: Spree::Vendor do
    name { FFaker::Company.name }
    about_us { 'About us...' }
    contact_us { 'Contact us...' }
    state { :active }
  end
end