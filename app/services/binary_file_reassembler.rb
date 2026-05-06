# typed: true
# frozen_string_literal: true

require "digest"
require "tempfile"

class BinaryFileReassembler
  Result = Data.define(:s3_key, :checksum, :byte_size)

  class ChecksumMismatch < StandardError
  end

  class << self
    def call(csv_import:, bucket:, s3_client:)
      new(csv_import, bucket, s3_client).call
    end
  end

  def initialize(csv_import, bucket, s3_client)
    @csv_import = csv_import
    @bucket = bucket
    @s3_client = s3_client
  end

  def call
    chunks = @csv_import.csv_import_chunks.order(:chunk_index).to_a
    raise ArgumentError, "no chunks to reassemble" if chunks.empty?
    raise ArgumentError, "chunks are not complete" if chunks.any? { |chunk| !chunk.completed? }

    Tempfile.create(%w[binary-reassembly- .bin], binmode: true) do |tempfile|
      copy_chunks_to(tempfile, chunks)
      tempfile.flush
      tempfile.rewind

      checksum = Digest::SHA256.file(tempfile.path).hexdigest
      verify_checksum!(checksum)

      tempfile.rewind
      key = "#{@csv_import.s3_prefix_or_default}/reassembled/#{sanitized_file_name}"
      @s3_client.put_object(bucket: @bucket, key: key, body: tempfile, content_type: @csv_import.content_type)
      Result.new(s3_key: key, checksum: checksum, byte_size: tempfile.size)
    end
  end

  private

  def copy_chunks_to(tempfile, chunks)
    chunks.each do |chunk|
      before = tempfile.pos
      object = @s3_client.get_object(bucket: @bucket, key: chunk.s3_key)
      IO.copy_stream(object.body, tempfile)
      copied = tempfile.pos - before
      raise IOError, "chunk #{chunk.id} byte size mismatch" unless copied == chunk.byte_size
    end
  end

  def verify_checksum!(checksum)
    return if @csv_import.source_checksum.blank? || @csv_import.source_checksum == checksum

    raise ChecksumMismatch, "reassembled checksum mismatch"
  end

  def sanitized_file_name
    File.basename(@csv_import.file_name.to_s).presence || "reassembled.bin"
  end
end
