module Spree
  module ProductDecorator
    def self.prepended(base)
      base.attr_accessor :detail
    end
  end
end

# patch attr detail, details attrs for rich edit need to move to other spree extensions
Spree::Product.prepend(Spree::ProductDecorator) if !Spree::Product.column_names.include?('detail')