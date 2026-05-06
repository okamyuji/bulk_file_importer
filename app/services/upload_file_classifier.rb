# typed: true
# frozen_string_literal: true

require "csv"

class UploadFileClassifier
  CSV_TYPES = %w[text/csv application/csv application/vnd.ms-excel].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime].freeze
  BINARY_TYPES = (IMAGE_TYPES + VIDEO_TYPES).freeze

  Result = Data.define(:input_kind, :content_type, :media_kind)

  class UnsupportedFileType < StandardError
  end

  class CsvHeaderMismatch < UnsupportedFileType
  end

  class << self
    def call(file:, target_kind:, requested_input_kind: nil)
      new(file, target_kind, requested_input_kind.presence).call
    end
  end

  def initialize(file, target_kind, requested_input_kind)
    @file = file
    @target_kind = target_kind
    @requested_input_kind = requested_input_kind
  end

  def call
    content_type = detected_content_type
    result = classify(content_type)
    validate_requested_kind!(result)
    validate_target_kind!(result)
    result
  end

  private

  attr_reader :file, :target_kind, :requested_input_kind

  def detected_content_type
    file.tempfile.rewind
    Marcel::MimeType.for(file.tempfile, name: file.original_filename).tap { file.tempfile.rewind }
  end

  def classify(content_type)
    if csv_type?(content_type)
      raise CsvHeaderMismatch, csv_header_mismatch_message unless valid_csv_header?

      Result.new(input_kind: "csv", content_type: content_type, media_kind: "csv")
    elsif IMAGE_TYPES.include?(content_type)
      Result.new(input_kind: "binary", content_type: content_type, media_kind: "image")
    elsif VIDEO_TYPES.include?(content_type)
      Result.new(input_kind: "binary", content_type: content_type, media_kind: "video")
    else
      raise UnsupportedFileType, "unsupported file type: #{content_type.inspect}"
    end
  end

  def csv_type?(content_type)
    CSV_TYPES.include?(content_type) || File.extname(file.original_filename.to_s).casecmp?(".csv")
  end

  def valid_csv_header?
    return false unless CsvImport::CSV_TARGET_KINDS.include?(target_kind)

    file.tempfile.rewind
    header = file.tempfile.gets
    return false if header.blank?

    header = header.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    parsed = CSV.parse_line(header)
    parsed == CsvRowMapper.expected_headers(target_kind)
  rescue CSV::MalformedCSVError, Encoding::InvalidByteSequenceError, ArgumentError, IOError, SystemCallError
    false
  ensure
    file.tempfile.rewind
  end

  def csv_header_mismatch_message
    expected =
      if CsvImport::CSV_TARGET_KINDS.include?(target_kind)
        CsvRowMapper.expected_headers(target_kind).join(",")
      else
        "a supported CSV target"
      end
    "csv headers do not match #{target_kind.inspect}; expected #{expected}"
  end

  def validate_requested_kind!(result)
    return if requested_input_kind.blank? || requested_input_kind == result.input_kind

    raise UnsupportedFileType, "file is #{result.input_kind}, not #{requested_input_kind}"
  end

  def validate_target_kind!(result)
    valid =
      if result.input_kind == "csv"
        CsvImport::CSV_TARGET_KINDS.include?(target_kind)
      else
        CsvImport::BINARY_TARGET_KINDS.include?(target_kind)
      end
    raise UnsupportedFileType, "invalid target_kind for #{result.input_kind}: #{target_kind.inspect}" unless valid
  end
end
