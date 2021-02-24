class Spree::ProductImportFile < ApplicationRecord
  belongs_to :user, class_name: "#{Spree.user_class}"
  has_one_attached :file

  enum status: %i[pending :progress  success failed]

  validates :name, presence: true
  validates :file, presence: true
  validates :file, attached: true, content_type: %i[csv]

  validate :correct_mine_type

  ALLOW_FORMATS = %w(text/csv).freeze

  def correct_mine_type

    if file.attached? && !file.content_type.in?(Spree::ProductImportFile::ALLOW_FORMATS)
      errors.add(:file, "format #{file.content_type} is not listed in #{Spree::ProductImportFile::ALLOW_FORMATS}")
    end
  end

end
