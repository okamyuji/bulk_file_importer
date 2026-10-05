# typed: true
# frozen_string_literal: true

# storage.yml・AppS3・cors.rb は開発用の既定値に倒れるので、本番で未設定だと別バケットや
# localhost 許可のまま黙って起動する。それを防ぐため production では起動時に止める。
# ECS は未設定の値を空文字で渡し得るので、空文字も未設定として扱う。
# Dockerfile の assets:precompile は本番の値を渡さずに production で起動するので、そこでだけ止めない。
# 並べて渡した db:prepare なども検査なしで走らないよう、precompile 単独のときだけに限る。
module RequiredProductionEnv
  KEYS = %w[S3_BUCKET FRONTEND_ORIGIN].freeze

  def self.verify!(env:, production:, rake_tasks:)
    return unless production
    return if rake_tasks == ["assets:precompile"]

    missing = KEYS.select { |key| env[key].blank? }
    raise "#{missing.join(", ")}未設定" if missing.any?
  end
end

RequiredProductionEnv.verify!(
  env: ENV,
  production: Rails.env.production?,
  rake_tasks: defined?(Rake.application) ? Rake.application.top_level_tasks : [],
)
