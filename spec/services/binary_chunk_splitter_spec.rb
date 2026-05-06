# frozen_string_literal: true

require "rails_helper"

RSpec.describe BinaryChunkSplitter do
  let(:fake) { FakeS3.new }

  def call(bytes, chunk_bytes: 4)
    described_class.call(
      io: StringIO.new(bytes),
      s3_prefix: "imports/binary/99",
      bucket: "b",
      s3_client: fake,
      chunk_bytes: chunk_bytes,
    )
  end

  it "splits bytes into fixed-size chunks and preserves contents" do
    result = call("abcdefghij", chunk_bytes: 4)

    expect(result.total_bytes).to eq(10)
    expect(result.total_chunks).to eq(3)
    expect(result.chunks.map(&:byte_size)).to eq([4, 4, 2])
    expect(result.source_checksum).to eq(Digest::SHA256.hexdigest("abcdefghij"))

    rejoined = result.chunks.map { |chunk| fake.get_object(bucket: "b", key: chunk.s3_key).body.read }.join
    expect(rejoined).to eq("abcdefghij")
  end

  it "does not treat whitespace-only chunks as EOF" do
    result = call("    abc", chunk_bytes: 4)

    expect(result.total_bytes).to eq(7)
    expect(result.chunks.map(&:byte_size)).to eq([4, 3])
  end

  it "does not treat invalid text encoding as an error" do
    bytes = String.new("\xFF\xD8\x00\xFE".b)
    result = call(bytes, chunk_bytes: 2)

    expect(result.total_bytes).to eq(4)
    expect(result.total_chunks).to eq(2)
  end

  it "fails on an empty file" do
    expect { call("") }.to raise_error(ArgumentError, /empty/)
  end
end
