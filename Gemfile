source "https://rubygems.org"

# 3.4.8 をローカルでは固定しつつ、DHI distroless ランタイムは 3.4 系の最新パッチに
# 揃わないことがある（記事より：builder と runtime で 3.4.9 / 3.4.5 のように
# パッチ違い）ため、Gemfile 側は `~>` で許容幅を取って RUBY_VERSION 厳密一致で
# 落ちないようにする。
ruby "~> 3.4"

# --- Core ---
gem "rails", "~> 8.1.3"
gem "propshaft"
gem "mysql2", "~> 0.5"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "thruster", require: false
gem "image_processing", "~> 2.0"
# DHI distroless ランタイムにはシステム tzdata が無く、ActiveSupport が
# `TZInfo::DataSourceNotFound` で起動失敗する。Ruby 側で時刻データを解決する
# ため、platforms 制限を外して全 OS で読み込ませる。
gem "tzinfo-data"
gem "rack-cors"

# --- DB-backed adapters (Rails 8 defaults) ---
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# --- Auth ---
gem "devise"
gem "devise-jwt"
gem "pundit"

# --- Serialization ---
gem "alba"

# --- AWS (ActiveStorage S3 + direct S3 for chunk splitter) ---
gem "aws-sdk-s3", require: false

# --- Type checking ---
gem "sorbet-runtime"

# --- CSV ---
gem "csv"

# --- N+1 クエリ検知 ---
# config/environments/{development,production}.rb から `Bullet.*` を参照しているため、
# 本番でもロードされる必要がある。`group :development, :test` に閉じ込めると
# RAILS_ENV=production での `assets:precompile` 実行時に
# `NameError: uninitialized constant Bullet` で落ちる。
gem "bullet"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "syntax_tree", require: false
  gem "erb_lint", require: false

  # Sorbet / Tapioca
  gem "sorbet", require: false
  gem "tapioca", require: false, platforms: %i[ruby]

  # RSpec
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
end

group :test do
  gem "webmock"
  gem "vcr"
  gem "simplecov", require: false
  gem "rails-controller-testing"
end

group :development do
  gem "web-console"
  gem "foreman", require: false
end

group :development, :test do
  gem "dotenv-rails"
end
