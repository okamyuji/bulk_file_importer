# typed: true
# frozen_string_literal: true

require "digest"

class BinaryChunkJob < ApplicationJob
  queue_as :csv_chunk

  retry_on StandardError, wait: :polynomially_longer, attempts: 3, jitter: 0.15

  def perform(chunk_id)
    chunk = CsvImportChunk.lock.find(chunk_id)
    Current.csv_import_id = chunk.csv_import_id
    return if chunk.completed?

    chunk.update!(status: "processing")
    csv_import = T.must(chunk.csv_import)

    checksum = checksum_for(chunk)
    chunk.update!(status: "completed", processed_rows: 0, failed_rows: 0, checksum: checksum, error_details: nil)

    AuditLogger.event(
      "binary_chunk.completed",
      chunk_id: chunk.id,
      chunk_index: chunk.chunk_index,
      byte_size: chunk.byte_size,
    )

    CsvImportChannel.broadcast_chunk_completed(chunk)
    CsvImportFinalizerJob.perform_later(csv_import.id) if csv_import.finish_one_chunk!
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    csv_import_id = chunk&.csv_import_id
    if csv_import_id
      csv_import = CsvImport.find_by(id: csv_import_id)
      CsvImportFinalizerJob.perform_later(csv_import_id) if csv_import&.finish_one_chunk!
    end

    CsvImportChunk.where(id: chunk_id).update_all(
      status: "failed",
      error_details: [{ fatal: e.message }],
      retry_count: (chunk&.retry_count.to_i) + 1,
    )
    AuditLogger.event(
      "binary_chunk.failed",
      chunk_id: chunk_id,
      error_class: e.class.name,
      error_message: e.message[0, 200],
    )
    raise
  end

  private

  def checksum_for(chunk)
    object = AppS3.client.get_object(bucket: AppS3.bucket, key: chunk.s3_key)
    Digest::SHA256.hexdigest(object.body.read)
  end
end
