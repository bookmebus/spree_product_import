module SpreeProductImport
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_product_import'

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    # Add assets to the asset pipeline
    initializer 'spree_product_import.assets' do |app|
      app.config.assets.precompile += %w[
        spree/backend/product_import_table.js
        spree/backend/spree_product_import.js
      ]
    end

    initializer 'spree_product_import.environment', before: :load_config_initializers do |_app|
      SpreeProductImport::Config = SpreeProductImport::Configuration.new
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
