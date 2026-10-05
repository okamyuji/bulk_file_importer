# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvChunkJob do
  let(:user) { create(:user) }

  let(:csv_body) do
    header = "recorded_on,customer_code,product_code,quantity,unit_price,amount,memo\n"
    rows = %w[
      2026-04-01,C001,P001,2,100.50,201.00,ok1
      2026-04-02,C002,P001,3,100.50,301.50,ok2
      not-a-date,CX,PX,1,100,100,bad_date
      2026-04-05,C003,P003,-1,50,100,neg_qty
    ].join("\n")
    header + rows
  end

  let(:file_import) do
    create(:file_import, user: user, target_kind: "sales_record", status: "processing", s3_prefix: "file_imports/ci")
  end

  let(:chunk) do
    file_import.file_import_chunks.create!(
      chunk_index: 0,
      start_row: 1,
      end_row: 4,
      status: "pending",
      s3_key: "file_imports/ci/chunk_000000.csv",
    )
  end

  before { AppS3.client.put_object(bucket: AppS3.bucket, key: chunk.s3_key, body: csv_body) }

  it "inserts valid rows via upsert_all and records failures" do
    expect { described_class.perform_now(chunk.id) }.to change(SalesRecord, :count).by(2)

    chunk.reload
    expect(chunk.status).to eq("completed_with_errors")
    expect(chunk.processed_rows).to eq(2)
    expect(chunk.failed_rows).to eq(2)
    expect(chunk.error_details.size).to eq(2)
  end

  it "is idempotent — re-running does not duplicate rows" do
    described_class.perform_now(chunk.id)
    chunk.update!(status: "pending") # force re-entry
    expect { described_class.perform_now(chunk.id) }.not_to change(SalesRecord, :count)
  end

  it "marks the chunk failed, increments retry_count and logs csv_chunk.failed when the chunk body is missing" do
    missing =
      file_import.file_import_chunks.create!(
        chunk_index: 1,
        start_row: 5,
        end_row: 5,
        status: "pending",
        s3_key: "file_imports/ci/missing.csv",
      )
    allow(AuditLogger).to receive(:event)

    expect { described_class.new.perform(missing.id) }.to raise_error(StandardError, /missing/)

    missing.reload
    expect(missing.status).to eq("failed")
    expect(missing.error_details).to eq([{ "fatal" => "RuntimeError" }])
    expect(missing.retry_count).to eq(1)
    expect(AuditLogger).to have_received(:event).with(
      "csv_chunk.failed",
      chunk_id: missing.id,
      error_class: a_kind_of(String),
      error_message: a_string_matching(/missing/),
    )
  end

  it "skips already-completed chunks (at-least-once delivery safety)" do
    chunk.update!(status: "completed", processed_rows: 999)
    expect { described_class.perform_now(chunk.id) }.not_to change(SalesRecord, :count)
  end
end
