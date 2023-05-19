module SpreeProductImport
  module ProductDecorator
    def self.prepended(base)
      base.attr_accessor :detail
    end
  end
end

# patch attr detail, details attrs for rich edit need to move to other spree extensions
Spree::Product.prepend SpreeProductImport::ProductDecorator unless Spree::Product.included_modules.include?(SpreeProductImport::ProductDecorator)