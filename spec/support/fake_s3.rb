# frozen_string_literal: true

require "stringio"
require "digest"

# In-memory S3 stub used by specs so CsvChunkSplitter / CsvChunkJob can run end-to-end
# without hitting LocalStack.
class FakeS3
  Response = Struct.new(:body)
  MultipartUpload = Struct.new(:upload_id)
  CopyPartResult = Struct.new(:etag)
  UploadPartCopyResult = Struct.new(:copy_part_result)

  def initialize
    @store = {}
    @multipart_uploads = {}
    @next_upload_id = 0
  end

  def put_object(bucket:, key:, body:, **_options)
    @store["#{bucket}/#{key}"] = body.is_a?(String) ? body.dup : body.read
    Response.new(StringIO.new(""))
  end

  def copy_object(bucket:, key:, copy_source:, **_options)
    @store["#{bucket}/#{key}"] = source_content(copy_source).dup
    Response.new(StringIO.new(""))
  end

  def create_multipart_upload(bucket:, key:, **_options)
    @next_upload_id += 1
    upload_id = "upload-#{@next_upload_id}"
    @multipart_uploads[upload_id] = { bucket: bucket, key: key, parts: {} }
    MultipartUpload.new(upload_id)
  end

  def upload_part_copy(bucket:, key:, upload_id:, part_number:, copy_source:, **_options)
    upload = @multipart_uploads.fetch(upload_id)
    raise "multipart target mismatch" unless upload[:bucket] == bucket && upload[:key] == key

    content = source_content(copy_source).dup
    upload[:parts][part_number] = content
    UploadPartCopyResult.new(CopyPartResult.new(Digest::MD5.hexdigest(content)))
  end

  def complete_multipart_upload(bucket:, key:, upload_id:, multipart_upload:)
    upload = @multipart_uploads.delete(upload_id)
    parts = multipart_upload.fetch(:parts).sort_by { |part| part.fetch(:part_number) }
    @store["#{bucket}/#{key}"] = parts.map { |part| upload[:parts].fetch(part.fetch(:part_number)) }.join
    Response.new(StringIO.new(""))
  end

  def abort_multipart_upload(bucket:, key:, upload_id:)
    @multipart_uploads.delete(upload_id)
    Response.new(StringIO.new(""))
  end

  def get_object(bucket:, key:)
    content = @store["#{bucket}/#{key}"] or raise "missing #{bucket}/#{key}"
    Response.new(StringIO.new(content))
  end

  def delete_object(bucket:, key:)
    @store.delete("#{bucket}/#{key}")
    Response.new(StringIO.new(""))
  end

  def keys
    @store.keys
  end

  private

  def source_content(copy_source)
    @store.fetch(copy_source)
  end
end
