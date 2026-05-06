# frozen_string_literal: true

require "rails_helper"

RSpec.describe BinaryFileReassembler do
  let(:user) { create(:user) }
  let(:source_bytes) { "aaabbbbcc".b }
  let(:source_checksum) { Digest::SHA256.hexdigest(source_bytes) }
  let(:csv_import) do
    create(
      :csv_import,
      user: user,
      input_kind: "binary",
      target_kind: "binary_asset",
      file_name: "sample.png",
      content_type: "image/png",
      byte_size: source_bytes.bytesize,
      total_bytes: source_bytes.bytesize,
      total_chunks: 3,
      source_checksum: source_checksum,
      s3_prefix: "imports/binary/reassemble",
    )
  end

  def make_chunk(index, bytes, start_byte:)
    chunk =
      csv_import.csv_import_chunks.create!(
        chunk_index: index,
        status: "completed",
        start_byte: start_byte,
        end_byte: start_byte + bytes.bytesize - 1,
        byte_size: bytes.bytesize,
        s3_key: "imports/binary/reassemble/chunk_#{format("%06d", index)}.bin",
      )
    AppS3.client.put_object(bucket: AppS3.bucket, key: chunk.s3_key, body: bytes)
    chunk
  end

  it "reassembles completed chunks in chunk_index order" do
    make_chunk(2, "cc", start_byte: 7)
    make_chunk(0, "aaa", start_byte: 0)
    make_chunk(1, "bbbb", start_byte: 3)

    result = described_class.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    body = AppS3.client.get_object(bucket: AppS3.bucket, key: result.s3_key).body.read

    expect(body).to eq(source_bytes)
    expect(result.checksum).to eq(source_checksum)
    expect(result.s3_key).to end_with("/reassembled/reassembled-#{csv_import.id}.bin")
  end

  it "rejects checksum mismatches" do
    csv_import.update!(source_checksum: Digest::SHA256.hexdigest("different"), total_chunks: 1)
    make_chunk(0, source_bytes, start_byte: 0)

    expect {
      described_class.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    }.to raise_error(BinaryFileReassembler::ChecksumMismatch)
  end

  it "rejects missing source checksums" do
    csv_import.update!(source_checksum: nil, total_chunks: 1)
    make_chunk(0, source_bytes, start_byte: 0)

    expect {
      described_class.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    }.to raise_error(BinaryFileReassembler::MissingSourceChecksum)
  end

  it "rejects missing chunk indices" do
    make_chunk(0, "aaa", start_byte: 0)
    make_chunk(2, "cc", start_byte: 7)

    expect {
      described_class.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    }.to raise_error(ArgumentError, /expected 3 chunks/)
  end

  it "rejects non-contiguous byte ranges" do
    make_chunk(0, "aaa", start_byte: 0)
    make_chunk(1, "bbbb", start_byte: 4)
    make_chunk(2, "cc", start_byte: 8)

    expect {
      described_class.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    }.to raise_error(ArgumentError, /byte ranges/)
  end
end
