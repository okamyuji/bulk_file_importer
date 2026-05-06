# typed: true
# frozen_string_literal: true

class ImportSplitter
  class << self
    def call(csv_import:, io:, bucket:, s3_client:)
      new(csv_import, io, bucket, s3_client).call
    end
  end

  def initialize(csv_import, io, bucket, s3_client)
    @csv_import = csv_import
    @io = io
    @bucket = bucket
    @s3_client = s3_client
  end

  def call
    case @csv_import.input_kind
    when "csv"
      CsvChunkSplitter.call(
        io: @io,
        s3_prefix: @csv_import.s3_prefix_or_default,
        bucket: @bucket,
        s3_client: @s3_client,
      )
    when "binary"
      BinaryChunkSplitter.call(
        io: @io,
        s3_prefix: @csv_import.s3_prefix_or_default,
        bucket: @bucket,
        s3_client: @s3_client,
      )
    else
      raise ArgumentError, "unknown input_kind: #{@csv_import.input_kind.inspect}"
    end
  end
end
