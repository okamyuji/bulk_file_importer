# frozen_string_literal: true

require "rails_helper"

RSpec.describe RequiredProductionEnv do
  let(:complete_env) { { "S3_BUCKET" => "bucket", "FRONTEND_ORIGIN" => "https://app.example.com" } }

  def verify(env:, production: true, rake_tasks: [])
    described_class.verify!(env:, production:, rake_tasks:)
  end

  it "passes in production when every required variable is set" do
    expect { verify(env: complete_env) }.not_to raise_error
  end

  it "raises in production when S3_BUCKET is missing" do
    expect { verify(env: complete_env.except("S3_BUCKET")) }.to raise_error(RuntimeError, "S3_BUCKET未設定")
  end

  it "raises in production when FRONTEND_ORIGIN is missing" do
    expect { verify(env: complete_env.except("FRONTEND_ORIGIN")) }.to raise_error(RuntimeError, "FRONTEND_ORIGIN未設定")
  end

  it "treats an empty or blank value as missing" do
    env = complete_env.merge("S3_BUCKET" => "", "FRONTEND_ORIGIN" => "  ")

    expect { verify(env:) }.to raise_error(RuntimeError, "S3_BUCKET, FRONTEND_ORIGIN未設定")
  end

  it "skips the check outside production" do
    expect { verify(env: {}, production: false) }.not_to raise_error
  end

  it "skips the check when only assets:precompile runs" do
    expect { verify(env: {}, rake_tasks: ["assets:precompile"]) }.not_to raise_error
  end

  it "still checks when assets:precompile runs together with another task" do
    expect { verify(env: {}, rake_tasks: %w[assets:precompile db:prepare]) }.to raise_error(RuntimeError, /未設定/)
  end

  it "still checks for other rake tasks" do
    expect { verify(env: {}, rake_tasks: ["db:migrate"]) }.to raise_error(RuntimeError, /未設定/)
  end
end
