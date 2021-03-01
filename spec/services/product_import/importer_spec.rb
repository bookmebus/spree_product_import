require 'spec_helper'
require 'spree_multi_vendor/factories'

RSpec.describe ProductImport::Importer, type: :services do
  let!(:vendor) { create(:vendor, name: "Zando Fashion") }
  let!(:prototype) { create(:prototype, name: 'Men Shirt') }
  let!(:shipping_category) { create(:shipping_category, name: 'Shipping by VTENH')}
  let!(:tax_category) { create(:tax_category, name: 'VAT Incl.')}

  describe "" do
    it "read" do

      import_file = create(:product_import_file)
      importer = ProductImport::Importer.new(import_file)

      importer.call
    end
  end
end