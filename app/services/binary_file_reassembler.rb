# typed: true
# frozen_string_literal: true

require "digest"

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

    checksum = checksum_for(chunks)
    verify_checksum!(checksum)

    key = "#{@csv_import.s3_prefix_or_default}/reassembled/#{sanitized_file_name}"
    copy_chunks_on_s3(chunks, key)
    Result.new(s3_key: key, checksum: checksum, byte_size: chunks.sum(&:byte_size))
  end

  private

  def checksum_for(chunks)
    digest = Digest::SHA256.new
    chunks.each do |chunk|
      object = @s3_client.get_object(bucket: @bucket, key: chunk.s3_key)
      copied = 0
      while (bytes = object.body.read(1.megabyte))
        copied += bytes.bytesize
        digest.update(bytes)
      end
      raise IOError, "chunk #{chunk.id} byte size mismatch" unless copied == chunk.byte_size
    end
    digest.hexdigest
  end

  def copy_chunks_on_s3(chunks, key)
    if chunks.one?
      @s3_client.copy_object(
        bucket: @bucket,
        copy_source: copy_source_for(T.must(chunks.first)),
        key: key,
        content_type: @csv_import.content_type,
        metadata_directive: "REPLACE",
      )
    else
      multipart_copy(chunks, key)
    end
  end

  def multipart_copy(chunks, key)
    upload = @s3_client.create_multipart_upload(bucket: @bucket, key: key, content_type: @csv_import.content_type)
    upload_id = upload.upload_id
    parts =
      chunks.each_with_index.map do |chunk, index|
        response =
          @s3_client.upload_part_copy(
            bucket: @bucket,
            key: key,
            upload_id: upload_id,
            part_number: index + 1,
            copy_source: copy_source_for(chunk),
          )
        { etag: response.copy_part_result.etag, part_number: index + 1 }
      end

    @s3_client.complete_multipart_upload(
      bucket: @bucket,
      key: key,
      upload_id: upload_id,
      multipart_upload: {
        parts: parts,
      },
    )
  rescue StandardError
    @s3_client.abort_multipart_upload(bucket: @bucket, key: key, upload_id: upload_id) if upload_id
    raise
  end

  def copy_source_for(chunk)
    "#{@bucket}/#{chunk.s3_key}"
  end

  def verify_checksum!(checksum)
    return if @csv_import.source_checksum.blank? || @csv_import.source_checksum == checksum

    raise ChecksumMismatch, "reassembled checksum mismatch"
  end

  def sanitized_file_name
    File.basename(@csv_import.file_name.to_s).presence || "reassembled.bin"
  end
end
