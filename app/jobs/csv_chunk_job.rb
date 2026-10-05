# typed: true
# frozen_string_literal: true

require "csv"

class CsvChunkJob < ApplicationJob
  include ChunkFailureRecording

  queue_as :csv_chunk

  BATCH_SIZE = 100

  retry_on StandardError, wait: :polynomially_longer, attempts: 3, jitter: 0.15

  def perform(chunk_id)
    chunk = FileImportChunk.lock.find(chunk_id)
    Current.file_import_id = chunk.file_import_id
    # Already-successful chunks are skipped to guarantee idempotency under Solid Queue's at-least-once delivery.
    return if chunk.completed?

    chunk.update!(status: "processing")

    file_import = T.must(chunk.file_import)
    target_class = target_class_for(file_import.target_kind)

    csv_body = fetch_chunk_body(chunk)

    valid_batch = []
    error_details = []
    total_in_chunk = 0
    invalid_count = 0

    CSV
      .parse(csv_body, headers: true, liberal_parsing: true)
      .each
      .with_index(T.must(chunk.start_row)) do |row, row_num|
        total_in_chunk += 1
        result = map_and_validate(row, file_import, target_class, row_num)

        if result[:ok]
          valid_batch << result[:attrs]
        else
          invalid_count += 1
          error_details << result[:error]
        end

        if valid_batch.size >= BATCH_SIZE
          db_failures = flush_batch(target_class, valid_batch)
          error_details.concat(db_failures)
          invalid_count += db_failures.size
          valid_batch = []
        end
      end

    if valid_batch.any?
      db_failures = flush_batch(target_class, valid_batch)
      error_details.concat(db_failures)
      invalid_count += db_failures.size
    end

    processed = total_in_chunk - invalid_count
    final_status = error_details.empty? ? "completed" : "completed_with_errors"

    chunk.update!(
      status: final_status,
      processed_rows: processed,
      failed_rows: invalid_count,
      error_details: error_details,
    )

    AuditLogger.event(
      "csv_chunk.completed",
      chunk_id: chunk.id,
      chunk_index: chunk.chunk_index,
      status: final_status,
      processed_rows: processed,
      failed_rows: invalid_count,
    )

    broadcast_chunk_completed(chunk)
    # remaining_chunksを0にしたワーカーだけがFinalizerを起動する。
    # これでFinalizerのenqueue/実行回数がインポートあたり1回に収まる。
    FileImportFinalizerJob.perform_later(file_import.id) if file_import.finish_one_chunk!
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    # 致命的エラー時はremaining_chunksをデクリメントする成功パスを通らない。
    # ここで明示的にデクリメントしないと、全チャンクが失敗した場合に
    # Finalizerが起動せずインポートのステータスがfailedに確定しない。
    file_import_id = chunk&.file_import_id
    if file_import_id
      file_import = FileImport.find_by(id: file_import_id)
      FileImportFinalizerJob.perform_later(file_import_id) if file_import&.finish_one_chunk!
    end
    record_chunk_failure(chunk_id, chunk, e, "csv_chunk.failed")
    raise
  end

  private

  def fetch_chunk_body(chunk)
    AppS3.client.get_object(bucket: AppS3.bucket, key: chunk.s3_key).body.read
  end

  # Returns { ok: true, attrs: } or { ok: false, error: { row:, errors: [...] } }
  def map_and_validate(row, file_import, target_class, row_num)
    attrs =
      CsvRowMapper.call(target_kind: file_import.target_kind, row: row.to_h, base_key: file_import.idempotency_key)

    record = target_class.new(attrs)
    return { ok: false, error: { row: row_num, errors: record.errors.full_messages } } unless record.valid?

    attrs[:file_import_id] = file_import.id
    now = Time.current
    attrs[:created_at] = now
    attrs[:updated_at] = now
    { ok: true, attrs: attrs }
  rescue CsvRowMapper::RowError => e
    { ok: false, error: { row: row_num, errors: [e.message] } }
  end

  # Returns list of row-level failures that hit DB constraints during fallback.
  # MySQL does not accept :unique_by; it uses ON DUPLICATE KEY UPDATE across all
  # unique indexes (including idempotency_key), so we omit unique_by here.
  def flush_batch(target_class, attrs_list)
    target_class.upsert_all(attrs_list, returning: false)
    []
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("[CsvChunkJob] batch upsert failed, falling back row-by-row: #{e.message}")
    fallback_failures = []
    attrs_list.each do |attrs|
      begin
        target_class.upsert(attrs)
      rescue StandardError => row_e
        fallback_failures << { row: "db_fallback", errors: [row_e.message], idempotency_key: attrs[:idempotency_key] }
      end
    end
    fallback_failures
  end

  def target_class_for(kind)
    case kind
    when "sales_record"
      SalesRecord
    when "ledger_entry"
      LedgerEntry
    else
      raise ArgumentError, "unknown target_kind: #{kind.inspect}"
    end
  end

  def broadcast_chunk_completed(chunk)
    FileImportChannel.broadcast_chunk_completed(chunk)
    Rails.logger.info(
      "[CsvChunkJob] chunk_completed id=#{chunk.id} processed=#{chunk.processed_rows} failed=#{chunk.failed_rows} status=#{chunk.status}",
    )
  end
end
