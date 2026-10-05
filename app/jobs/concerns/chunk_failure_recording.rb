# typed: true
# frozen_string_literal: true

module ChunkFailureRecording
  private

  # chunk は lock.find 前に失敗すると nil になるため、更新は chunk_id で行う。
  def record_chunk_failure(chunk_id, chunk, error, event_name)
    # error_details は API で利用者に返る。例外文はバケット名・キー・SQL 断片を含み得るため監査ログにだけ残す。
    FileImportChunk.where(id: chunk_id).update_all(
      status: "failed",
      error_details: [{ fatal: error.class.name }],
      retry_count: (chunk&.retry_count.to_i) + 1,
    )
    AuditLogger.event(
      event_name,
      chunk_id: chunk_id,
      error_class: error.class.name,
      error_message: error.message[0, 200],
    )
  end
end
