# frozen_string_literal: true

require "rails_helper"
require "base64"

RSpec.describe UploadFileClassifier do
  def uploaded_file(name, content_type, bytes)
    path = Rails.root.join("tmp/#{name}")
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path.to_s, content_type)
  end

  let(:csv_bytes) do
    "recorded_on,customer_code,product_code,quantity,unit_price,amount,memo\n" \
      "2026-04-01,C1,P1,1,1,1,ok\n"
  end
  let(:png_bytes) do
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")
  end

  it "classifies a valid CSV as csv" do
    file = uploaded_file("valid.csv", "text/csv", csv_bytes)

    result = described_class.call(file: file, target_kind: "sales_record", requested_input_kind: "csv")

    expect(result.input_kind).to eq("csv")
  end

  it "classifies a PNG as binary image" do
    file = uploaded_file("image.png", "image/png", png_bytes)

    result = described_class.call(file: file, target_kind: "binary_asset", requested_input_kind: "binary")

    expect(result.input_kind).to eq("binary")
    expect(result.media_kind).to eq("image")
  end

  it "rejects a PNG requested as CSV" do
    file = uploaded_file("fake.csv", "text/csv", png_bytes)

    expect {
      described_class.call(file: file, target_kind: "sales_record", requested_input_kind: "csv")
    }.to raise_error(UploadFileClassifier::UnsupportedFileType)
  end
end
