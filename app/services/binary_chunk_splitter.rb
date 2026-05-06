# typed: true
# frozen_string_literal: true

class BinaryChunkSplitter
  DEFAULT_CHUNK_BYTES = 8.megabytes

  Chunk = Data.define(:index, :start_byte, :end_byte, :s3_key, :byte_size)
  Result = Data.define(:total_bytes, :total_chunks, :chunks)

  class << self
    def call(io:, s3_prefix:, bucket:, s3_client:, chunk_bytes: DEFAULT_CHUNK_BYTES)
      new(io, s3_prefix, bucket, s3_client, chunk_bytes).call
    end
  end

  def initialize(io, s3_prefix, bucket, s3_client, chunk_bytes)
    @io = io
    @s3_prefix = s3_prefix
    @bucket = bucket
    @s3_client = s3_client
    @chunk_bytes = chunk_bytes
  end

  def call
    offset = 0
    chunk_index = 0
    chunks = []

    loop do
      bytes = @io.read(@chunk_bytes)
      break if bytes.blank?

      bytes.force_encoding(Encoding::BINARY)
      start_byte = offset
      end_byte = offset + bytes.bytesize - 1
      key = "#{@s3_prefix}/chunk_#{chunk_index.to_s.rjust(6, "0")}.bin"
      @s3_client.put_object(bucket: @bucket, key: key, body: bytes, content_type: "application/octet-stream")

      chunks << Chunk.new(
        index: chunk_index,
        start_byte: start_byte,
        end_byte: end_byte,
        s3_key: key,
        byte_size: bytes.bytesize,
      )
      offset += bytes.bytesize
      chunk_index += 1
    end

    raise ArgumentError, "binary file is empty" if offset.zero?

    Result.new(total_bytes: offset, total_chunks: chunks.size, chunks: chunks)
  end
end
