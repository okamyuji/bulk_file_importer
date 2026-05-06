# typed: true
# frozen_string_literal: true

class BinaryAsset < ApplicationRecord
  STATUSES = %w[pending completed partially_failed failed].freeze

  belongs_to :csv_import

  validates :file_name, :content_type, :checksum, :idempotency_key, presence: true
  validates :byte_size, numericality: { greater_than: 0 }
  validates :idempotency_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
