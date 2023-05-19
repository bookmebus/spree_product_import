require 'spec_helper'

RSpec.describe Spree::ProductImportFile, type: :model do

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:file) }

    it { is_expected.to validate_attached_of(:file) }
    it { is_expected.to validate_content_type_of(:file).allowing(Spree::ProductImportFile::ALLOW_FORMATS) }
    it { is_expected.to validate_content_type_of(:file).rejecting('text/plain', 'text/xml') }
  end

  describe 'associations' do
    it { is_expected.to have_one_attached(:file) }
  end

  it "validates format of file" do
    import = build(:product_import_file_ok)
    result = import.valid?

    expect(result).to eq true
  end

  it "sets file_name attributes" do
    import = create(:product_import_file_ok)
    expect(import.file_name).to eq "product_import_ok.xlsx"
  end

  it "sets default status to active" do
    import = create(:product_import_file_ok)
    expect(import.active?).to eq true
  end

end
