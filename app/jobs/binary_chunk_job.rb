# typed: true
# frozen_string_literal: true

require "digest"

class BinaryChunkJob < ApplicationJob
  queue_as :csv_chunk

  retry_on StandardError, wait: :polynomially_longer, attempts: 3, jitter: 0.15

  def perform(chunk_id)
    chunk = mark_processing!(chunk_id)
    return unless chunk

    Current.csv_import_id = chunk.csv_import_id
    csv_import = T.must(chunk.csv_import)

    checksum = checksum_for(chunk)
    CsvImportChunk.transaction do
      chunk = CsvImportChunk.lock.find(chunk_id)
      chunk.update!(status: "completed", processed_rows: 0, failed_rows: 0, checksum: checksum, error_details: nil)
    end

    AuditLogger.event(
      "binary_chunk.completed",
      chunk_id: chunk.id,
      chunk_index: chunk.chunk_index,
      byte_size: chunk.byte_size,
    )

    CsvImportChannel.broadcast_chunk_completed(chunk)
    # CsvImportFinalizerJobは「全チャンクがterminal状態か」と「BinaryAssetが既に
    # completedか」を自前で確認するため、チャンクごとの冪等enqueueで安全に動作する。
    # 失敗チャンクが remaining_chunks を減らさない問題を抱えないよう、binary側は
    # finish_one_chunk! のカウンタに依存せず、常にFinalizerをenqueueする。
    CsvImportFinalizerJob.perform_later(csv_import.id)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    csv_import_id = chunk&.csv_import_id

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
    # 再試行が残っている間はFinalizerを起動しない。最終リトライで初めてチャンクが
    # 「永続的失敗」とみなせるため、ここでだけ直接enqueueする（finish_one_chunk!を
    # rescueから呼ぶと、retry中の一時的失敗まで残数を減らしてしまうため避ける）。
    CsvImportFinalizerJob.perform_later(csv_import_id) if csv_import_id && final_retry_attempt?
    raise
  end

  private

  def mark_processing!(chunk_id)
    CsvImportChunk.transaction do
      chunk = CsvImportChunk.lock.find(chunk_id)
      return nil if chunk.completed?

      chunk.update!(status: "processing")
      chunk
    end
  end

  def checksum_for(chunk)
    object = AppS3.client.get_object(bucket: AppS3.bucket, key: chunk.s3_key)
    digest = Digest::SHA256.new
    while (bytes = object.body.read(1.megabyte))
      digest.update(bytes)
    end
    digest.hexdigest
  ensure
    object&.body&.close if object&.body&.respond_to?(:close)
  end

  def final_retry_attempt?
    executions >= 3
  end
end
