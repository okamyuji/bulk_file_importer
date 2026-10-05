# typed: true
# frozen_string_literal: true

module ChunkFailureRecording
  private

  # chunk は lock.find 前に失敗すると nil になるため、更新は chunk_id で行う。
  def record_chunk_failure(chunk_id, chunk, error, event_name)
    # Rails' JSON column attribute handles serialization, so pass a plain array.
    FileImportChunk.where(id: chunk_id).update_all(
      status: "failed",
      error_details: [{ fatal: error.message }],
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
