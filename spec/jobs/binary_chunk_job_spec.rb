# frozen_string_literal: true

require "rails_helper"

RSpec.describe BinaryChunkJob do
  let(:user) { create(:user) }
  let(:csv_import) do
    create(
      :csv_import,
      user: user,
      input_kind: "binary",
      target_kind: "binary_asset",
      file_name: "sample.png",
      content_type: "image/png",
      byte_size: 3,
      total_bytes: 3,
      total_chunks: 1,
      remaining_chunks: 1,
      source_checksum: Digest::SHA256.hexdigest("abc"),
      status: "processing",
      s3_prefix: "imports/binary/chunk-job",
    )
  end
  let(:chunk) do
    csv_import.csv_import_chunks.create!(
      chunk_index: 0,
      status: "pending",
      start_byte: 0,
      end_byte: 2,
      byte_size: 3,
      s3_key: "imports/binary/chunk-job/missing.bin",
    )
  end

  it "does not enqueue the finalizer while a retryable binary chunk failure can still retry" do
    job = described_class.new
    allow(job).to receive(:executions).and_return(2)

    expect { job.perform(chunk.id) }.to raise_error(StandardError, /missing/)

    # 再試行中なのでFinalizerは起動しない。remaining_chunksも変更しない（rescueでは
    # finish_one_chunk! を呼ばない方針）。
    expect(csv_import.reload.remaining_chunks).to eq(1)
    expect(csv_import.csv_import_chunks.find(chunk.id).status).to eq("failed")
    expect(CsvImportFinalizerJob).not_to have_been_enqueued
  end

  it "enqueues the finalizer once the final retry has failed permanently" do
    job = described_class.new
    allow(job).to receive(:executions).and_return(3)

    expect { job.perform(chunk.id) }.to raise_error(StandardError, /missing/)

    # 永続的失敗が確定した時点でFinalizerに通知する。Finalizer自身が
    # 「pending/processing なチャンクが残っているか」を再確認する冪等構造のため、
    # remaining_chunksの減算には依存しない。
    expect(csv_import.csv_import_chunks.find(chunk.id).status).to eq("failed")
    expect(CsvImportFinalizerJob).to have_been_enqueued.with(csv_import.id)
  end
end
