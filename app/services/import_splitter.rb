# typed: true
# frozen_string_literal: true

class ImportSplitter
  class << self
    def call(file_import:, io:, bucket:, s3_client:)
      new(file_import, io, bucket, s3_client).call
    end
  end

  def initialize(file_import, io, bucket, s3_client)
    @file_import = file_import
    @io = io
    @bucket = bucket
    @s3_client = s3_client
  end

  def call
    splitter_class.call(io: @io, s3_prefix: @file_import.s3_prefix_or_default, bucket: @bucket, s3_client: @s3_client)
  end

  private

  def splitter_class
    case @file_import.input_kind
    when "csv"
      CsvChunkSplitter
    when "binary"
      BinaryChunkSplitter
    else
      raise ArgumentError, "unknown input_kind: #{@file_import.input_kind.inspect}"
    end
  end
end
