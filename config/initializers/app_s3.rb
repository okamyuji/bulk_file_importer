# typed: true
# frozen_string_literal: true

require "aws-sdk-s3"

# Wraps Aws::S3::Client so endpoint/bucket come from env and tests can swap it.
# Dev/test point at LocalStack (explicit credentials); prod/ECS uses IAM task role
# via the SDK's default credential chain (no explicit keys needed).
module AppS3
  class << self
    attr_writer :client, :bucket

    def client
      @client ||= build_client
    end

    def bucket
      @bucket ||= ENV.fetch("S3_BUCKET", "bulk-file-importer-dev")
    end

    def reset!
      @client = nil
      @bucket = nil
    end

    private

    def build_client
      params = { region: ENV.fetch("AWS_REGION", "us-east-1") }

      if ENV["S3_ENDPOINT"].present?
        params[:endpoint] = ENV["S3_ENDPOINT"]
        params[:force_path_style] = true
        params[:access_key_id] = ENV.fetch("AWS_ACCESS_KEY_ID", "test")
        params[:secret_access_key] = ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
      end

      Aws::S3::Client.new(**params)
    end
  end
end
