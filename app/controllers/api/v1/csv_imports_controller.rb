# typed: true
# frozen_string_literal: true

require "digest"

module Api
  module V1
    class CsvImportsController < Api::BaseController
      def index
        scope = policy_scope(CsvImport).recent.limit(100)
        render json: { data: CsvImportResource.new(scope).serializable_hash }
      end

      def show
        imp = CsvImport.find(params[:id])
        authorize imp
        render json: {
                 data: CsvImportResource.new(imp).serializable_hash,
                 chunks: CsvImportChunkResource.new(imp.csv_import_chunks.order(:chunk_index)).serializable_hash,
               }
      end

      def create
        authorize CsvImport, :create?

        file = params.require(:file)
        target_kind = params.require(:target_kind)
        classification =
          UploadFileClassifier.call(file: file, target_kind: target_kind, requested_input_kind: params[:input_kind])

        source_checksum = build_source_checksum(file)

        imp =
          CsvImport.create!(
            user: current_user,
            file_name: file.original_filename,
            input_kind: classification.input_kind,
            target_kind: target_kind,
            content_type: classification.content_type,
            byte_size: file.size,
            total_bytes: classification.input_kind == "binary" ? file.size : 0,
            source_checksum: source_checksum,
            status: "pending",
            idempotency_key: build_idempotency_key(file),
          )
        file.tempfile.rewind
        imp.source_file.attach(
          io: file.tempfile,
          filename: file.original_filename,
          content_type: classification.content_type,
        )
        imp.update!(s3_prefix: "imports/#{classification.input_kind}/#{imp.id}")

        Current.csv_import_id = imp.id
        AuditLogger.event(
          "csv_import.created",
          file_name: file.original_filename,
          byte_size: file.size,
          content_type: classification.content_type,
          input_kind: classification.input_kind,
          target_kind: target_kind,
          idempotency_prefix: imp.idempotency_key[0, 12],
        )

        CsvImportJob.perform_later(imp.id)

        render json: { data: CsvImportResource.new(imp).serializable_hash }, status: :accepted
      rescue UploadFileClassifier::UnsupportedFileType => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def retry
        imp = CsvImport.find(params[:id])
        authorize imp, :retry?
        Current.csv_import_id = imp.id
        result = CsvImportRetryService.call(imp)
        AuditLogger.event("csv_import.retried", retried_chunks: result.retried)
        render json: { retried: result.retried }, status: :accepted
      end

      private

      def build_idempotency_key(file)
        # 秒単位だと同一秒内の再送で衝突し得るため、マイクロ秒（%s%6N）まで含めて
        # 衝突確率を下げる。プラットフォーム依存の Time#to_f ではなく、明示フォーマットを使う
        user = T.must(current_user)
        timestamp = Time.current.strftime("%s%6N")
        Digest::SHA256.hexdigest("#{user.id}|#{file.original_filename}|#{file.size}|#{timestamp}")
      end

      def build_source_checksum(file)
        file.tempfile.rewind
        Digest::SHA256.file(file.tempfile.path).hexdigest
      ensure
        file.tempfile.rewind
      end
    end
  end
end
