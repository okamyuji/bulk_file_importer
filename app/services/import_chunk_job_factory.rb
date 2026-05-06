# typed: true
# frozen_string_literal: true

class ImportChunkJobFactory
  class << self
    def build(chunk)
      case chunk.csv_import.input_kind
      when "csv"
        CsvChunkJob.new(chunk.id)
      when "binary"
        BinaryChunkJob.new(chunk.id)
      else
        raise ArgumentError, "unknown input_kind: #{chunk.csv_import.input_kind.inspect}"
      end
    end
  end
end
