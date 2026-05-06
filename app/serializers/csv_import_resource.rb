# typed: true
# frozen_string_literal: true

class CsvImportResource
  include Alba::Resource

  attributes :id,
             :file_name,
             :input_kind,
             :target_kind,
             :content_type,
             :byte_size,
             :status,
             :total_rows,
             :processed_rows,
             :failed_rows,
             :total_bytes,
             :processed_bytes,
             :failed_bytes,
             :total_chunks,
             :idempotency_key,
             :source_checksum,
             :reassembled_s3_key,
             :reassembled_checksum,
             :error_message,
             :created_at,
             :updated_at

  attribute :progress do |imp|
    denominator = imp.progress_denominator.to_i
    next 0 if denominator.zero?

    (imp.progress_numerator.to_f / denominator * 100).round(1)
  end
end
