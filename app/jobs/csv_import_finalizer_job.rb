# typed: true
# frozen_string_literal: true

class CsvImportFinalizerJob < ApplicationJob
  queue_as :csv_import

  def perform(csv_import_id)
    csv_import = CsvImport.find(csv_import_id)
    chunks = csv_import.csv_import_chunks
    return if chunks.where(status: %w[pending processing]).exists?

    Current.csv_import_id = csv_import.id
    Current.user_id = csv_import.user_id

    if csv_import.binary?
      finalize_binary_import(csv_import, chunks)
    else
      finalize_csv_import(csv_import, chunks)
    end

    CsvImportChannel.broadcast_import_finalized(csv_import)
  end

  private

  def finalize_csv_import(csv_import, chunks)
    total_processed = chunks.sum(:processed_rows)
    total_failed = chunks.sum(:failed_rows)
    failed_chunks = chunks.where(status: "failed").count
    partial_chunks = chunks.where(status: "completed_with_errors").count

    new_status =
      if failed_chunks.positive? && total_processed.zero?
        "failed"
      elsif failed_chunks.positive?
        "partially_failed"
      elsif partial_chunks.positive?
        "completed_with_errors"
      else
        "completed"
      end

    csv_import.update!(status: new_status, processed_rows: total_processed, failed_rows: total_failed)

    AuditLogger.event(
      "csv_import.finalized",
      status: new_status,
      total_rows: csv_import.total_rows,
      processed_rows: total_processed,
      failed_rows: total_failed,
      failed_chunks: failed_chunks,
    )
  end

  def finalize_binary_import(csv_import, chunks)
    failed_chunks = chunks.where(status: "failed").count
    total_processed = chunks.where(status: %w[completed completed_with_errors]).sum(:byte_size)
    total_failed = chunks.where(status: "failed").sum(:byte_size)

    if failed_chunks.positive?
      new_status = total_processed.zero? ? "failed" : "partially_failed"
      csv_import.update!(status: new_status, processed_bytes: total_processed, failed_bytes: total_failed)
      upsert_binary_asset(csv_import, new_status)
      audit_binary_finalized(csv_import, new_status, failed_chunks)
      return
    end

    result = BinaryFileReassembler.call(csv_import: csv_import, bucket: AppS3.bucket, s3_client: AppS3.client)
    csv_import.update!(
      status: "completed",
      processed_bytes: total_processed,
      failed_bytes: 0,
      reassembled_s3_key: result.s3_key,
      reassembled_checksum: result.checksum,
    )
    upsert_binary_asset(csv_import, "completed")
    audit_binary_finalized(csv_import, "completed", 0)
  rescue StandardError => e
    csv_import.update!(status: "failed", error_message: e.message)
    upsert_binary_asset(csv_import, "failed")
    AuditLogger.event("binary_import.reassemble_failed", error_class: e.class.name, error_message: e.message[0, 200])
    raise
  end

  def upsert_binary_asset(csv_import, status)
    BinaryAsset
      .find_or_initialize_by(csv_import: csv_import)
      .tap do |asset|
        asset.assign_attributes(
          file_name: csv_import.file_name,
          content_type: csv_import.content_type || "application/octet-stream",
          byte_size: csv_import.byte_size,
          checksum: csv_import.source_checksum || csv_import.idempotency_key,
          reassembled_s3_key: csv_import.reassembled_s3_key,
          reassembled_checksum: csv_import.reassembled_checksum,
          status: status,
          idempotency_key: csv_import.idempotency_key,
          metadata: {
            input_kind: csv_import.input_kind,
          },
        )
        asset.save!
      end
  end

  def audit_binary_finalized(csv_import, status, failed_chunks)
    AuditLogger.event(
      "binary_import.finalized",
      status: status,
      total_bytes: csv_import.total_bytes,
      processed_bytes: csv_import.processed_bytes,
      failed_bytes: csv_import.failed_bytes,
      failed_chunks: failed_chunks,
    )
  end
end
