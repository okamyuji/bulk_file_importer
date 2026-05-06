# frozen_string_literal: true

FactoryBot.define do
  factory :binary_asset do
    association :csv_import, input_kind: "binary", target_kind: "binary_asset"
    file_name { "image.png" }
    content_type { "image/png" }
    byte_size { 10 }
    checksum { Digest::SHA256.hexdigest("binary") }
    status { "pending" }
    sequence(:idempotency_key) { |n| "binary-#{n}-#{SecureRandom.hex(4)}" }
  end
end
