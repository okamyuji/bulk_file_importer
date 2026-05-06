# typed: true
# frozen_string_literal: true

class CsvImportChunk < ApplicationRecord
  STATUSES = %w[pending processing completed completed_with_errors failed].freeze

  belongs_to :csv_import

  validates :chunk_index, presence: true, uniqueness: { scope: :csv_import_id }
  validates :start_row, :end_row, presence: true, numericality: { greater_than: 0 }, if: :csv_import_csv?
  validates :start_byte,
            :end_byte,
            :byte_size,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 0,
            },
            if: :csv_import_binary?
  validates :status, inclusion: { in: STATUSES }
  validates :s3_key, presence: true

  scope :pending_status, -> { where(status: "pending") }
  scope :failed_status, -> { where(status: "failed") }
  scope :in_progress, -> { where(status: %w[pending processing]) }

  def completed?
    %w[completed completed_with_errors].include?(status)
  end

  def final?
    %w[completed completed_with_errors failed].include?(status)
  end

  private

  def csv_import_csv?
    csv_import&.csv? != false
  end

  def csv_import_binary?
    csv_import&.binary? == true
  end
end
