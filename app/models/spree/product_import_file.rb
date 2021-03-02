module Spree
  class ProductImportFile < Spree::Base
    serialize :error, Hash
  
    ALLOW_FORMATS = %w(text/csv application/vnd.openxmlformats-officedocument.spreadsheetml.sheet).freeze
   
    belongs_to :user, class_name: "#{Spree.user_class}"
    has_one_attached :file

    enum status: %i[pending in_progress success failed]

    validates :name, presence: true
    validates :file, attached: true, content_type: ALLOW_FORMATS

    before_save :set_file_name

    def set_file_name
      self.file_name = file.blob.filename if file.attached?
    end
    
  end
end
