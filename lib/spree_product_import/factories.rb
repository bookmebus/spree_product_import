FactoryBot.define do
  # Define your Spree extensions Factories within this file to enable applications, and other extensions to use and override them.
  #
  # Example adding this to your spec_helper will load these Factories for use:
  # require 'spree_product_import/factories'

  GEM_ROOT = File.dirname(File.dirname(File.dirname(__FILE__)))

  Dir[File.join(GEM_ROOT, 'spec', 'factories', '**', '*.rb')].each do |factory|
    require(factory)
  end

end
