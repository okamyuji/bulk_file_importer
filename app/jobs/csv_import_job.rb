# typed: true
# frozen_string_literal: true

class CsvImportJob < ApplicationJob
  queue_as :csv_import

  def perform(csv_import_id)
    csv_import = CsvImport.find(csv_import_id)
    Current.csv_import_id = csv_import.id
    Current.user_id = csv_import.user_id
    return unless %w[pending failed].include?(csv_import.status)

    csv_import.update!(status: "splitting", error_message: nil, s3_prefix: csv_import.s3_prefix_or_default)
    AuditLogger.event("csv_import.splitting_started")

    result =
      ImportSourceOpener.call(csv_import) do |io|
        ImportSplitter.call(csv_import: csv_import, io: io, bucket: AppS3.bucket, s3_client: AppS3.client)
      end

    CsvImport.transaction do
      csv_import.update!(processing_attributes(csv_import, result))

      result.chunks.each { |c| csv_import.csv_import_chunks.create!(chunk_attributes(csv_import, c)) }
    end

    broadcast_split_started(csv_import)

    # チャンクジョブをbulk enqueueし、Solid QueueへのINSERTを
    # 1ラウンドトリップにまとめる。
    chunks = csv_import.csv_import_chunks.includes(:csv_import).order(:chunk_index)
    ActiveJob.perform_all_later(chunks.map { |chunk| ImportChunkJobFactory.build(chunk) })
  rescue StandardError => e
    CsvImport.where(id: csv_import_id).update_all(status: "failed", error_message: e.message)
    AuditLogger.event("csv_import.splitting_failed", error_class: e.class.name, error_message: e.message[0, 200])
    raise
  end

  private

  def processing_attributes(csv_import, result)
    attrs = {
      status: "processing",
      total_chunks: result.total_chunks,
      # 「未完了チャンク数」カウンタを総チャンク数で初期化する。
      # 最後のチャンク完了時にFinalizerを1回だけ起動するために使う
      # (CsvImport#finish_one_chunk!を参照)
      remaining_chunks: result.total_chunks,
    }
    if csv_import.binary?
      attrs[:total_bytes] = result.total_bytes
      attrs[:source_checksum] = result.source_checksum
    else
      attrs[:total_rows] = result.total_rows
    end
    attrs
  end

  def chunk_attributes(csv_import, chunk)
    attrs = { chunk_index: chunk.index, status: "pending", s3_key: chunk.s3_key }
    if csv_import.binary?
      attrs.merge!(start_byte: chunk.start_byte, end_byte: chunk.end_byte, byte_size: chunk.byte_size)
    else
      attrs.merge!(start_row: chunk.start_row, end_row: chunk.end_row)
    end
    attrs
  end

  def broadcast_split_started(csv_import)
    CsvImportChannel.broadcast_split_started(csv_import)
    Rails.logger.info(
      "[CsvImportJob] split_started csv_import_id=#{csv_import.id} input_kind=#{csv_import.input_kind} chunks=#{csv_import.total_chunks}",
    )
  end
end
