# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImportFinalizerJob, "binary imports" do
  let(:user) { create(:user) }
  let(:bytes) { "aaabbbbcc".b }
  let(:checksum) { Digest::SHA256.hexdigest(bytes) }
  let(:csv_import) do
    create(
      :csv_import,
      user: user,
      input_kind: "binary",
      target_kind: "binary_asset",
      file_name: "sample.png",
      content_type: "image/png",
      byte_size: bytes.bytesize,
      total_bytes: bytes.bytesize,
      total_chunks: 3,
      remaining_chunks: 0,
      source_checksum: checksum,
      status: "processing",
      s3_prefix: "imports/binary/finalizer",
    )
  end

  def make_chunk(index, chunk_bytes, status: "completed")
    chunk =
      csv_import.csv_import_chunks.create!(
        chunk_index: index,
        status: status,
        start_byte: index * 3,
        end_byte: index * 3 + chunk_bytes.bytesize - 1,
        byte_size: chunk_bytes.bytesize,
        s3_key: "imports/binary/finalizer/chunk_#{format("%06d", index)}.bin",
      )
    AppS3.client.put_object(bucket: AppS3.bucket, key: chunk.s3_key, body: chunk_bytes)
    chunk
  end

  it "reassembles all completed chunks and records a binary asset" do
    make_chunk(0, "aaa")
    make_chunk(1, "bbbb")
    make_chunk(2, "cc")

    described_class.perform_now(csv_import.id)

    csv_import.reload
    expect(csv_import.status).to eq("completed")
    expect(csv_import.processed_bytes).to eq(bytes.bytesize)
    expect(csv_import.reassembled_checksum).to eq(checksum)
    expect(AppS3.client.get_object(bucket: AppS3.bucket, key: csv_import.reassembled_s3_key).body.read).to eq(bytes)
    expect(csv_import.binary_asset.status).to eq("completed")
  end

  it "does not reassemble when a chunk failed" do
    make_chunk(0, "aaa")
    make_chunk(1, "bbbb", status: "failed")

    described_class.perform_now(csv_import.id)

    csv_import.reload
    expect(csv_import.status).to eq("partially_failed")
    expect(csv_import.reassembled_s3_key).to be_nil
  end
end
