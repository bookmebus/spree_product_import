require 'roo'
module ProductImport
  class XlsxHandler
    def initialize(product_import_file)
      @product_import_file = product_import_file

      @product_import_file.file.open do |file|
        @xlsx = Roo::Spreadsheet.open(file)
      end
    end

    def product_data!
      @xlsx.default_sheet = 'Main'
      @sheet  = @xlsx.sheet(0)
      self
    end

    def variant_data!
      @xlsx.default_sheet = 'Variant'
      @sheet  = @xlsx.sheet(1)
      self
    end

    def read(row, col)
      cell(row, col)
    end

    def cell(row, col)
      @sheet.cell(row, col)
    end

    def rows_count
      @sheet.last_row
    end

    def cols_count
      @sheet.last_column
    end
  end
end

