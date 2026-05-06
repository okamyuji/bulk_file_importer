# typed: true
# frozen_string_literal: true

class ImportSourceOpener
  class << self
    def call(csv_import, &block)
      new(csv_import).call(&block)
    end
  end

  def initialize(csv_import)
    @csv_import = csv_import
  end

  def call
    mode = @csv_import.binary? ? "rb" : "r:bom|utf-8"
    @csv_import.source_file.open { |tempfile| File.open(tempfile.path, mode) { |io| yield io } }
  end
end
