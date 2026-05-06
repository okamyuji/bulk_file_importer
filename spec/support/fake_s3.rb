# frozen_string_literal: true

require "stringio"

# In-memory S3 stub used by specs so CsvChunkSplitter / CsvChunkJob can run end-to-end
# without hitting LocalStack.
class FakeS3
  Response = Struct.new(:body)

  def initialize
    @store = {}
  end

  def put_object(bucket:, key:, body:, **_options)
    @store["#{bucket}/#{key}"] = body.is_a?(String) ? body.dup : body.read
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
end
