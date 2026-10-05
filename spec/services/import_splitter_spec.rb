# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportSplitter do
  let(:fake) { FakeS3.new }

  def call(file_import, body)
    described_class.call(file_import: file_import, io: StringIO.new(body), bucket: "b", s3_client: fake)
  end

  it "splits a csv import with CsvChunkSplitter under the import's s3 prefix" do
    file_import = build(:file_import, input_kind: "csv", s3_prefix: "imports/csv/spec")

    result = call(file_import, "h1,h2\nv1,x\nv2,y\n")

    expect(result).to be_a(CsvChunkSplitter::Result)
    expect(result.total_rows).to eq(2)
    expect(fake.keys).to all(start_with("b/imports/csv/spec/"))
  end

  it "splits a binary import with BinaryChunkSplitter under the import's s3 prefix" do
    file_import = build(:file_import, input_kind: "binary", s3_prefix: "imports/binary/spec")

    result = call(file_import, "abc")

    expect(result).to be_a(BinaryChunkSplitter::Result)
    expect(result.total_bytes).to eq(3)
    expect(fake.keys).to all(start_with("b/imports/binary/spec/"))
  end

  it "raises ArgumentError for an unknown input_kind" do
    file_import = build(:file_import, input_kind: "xml")

    expect { call(file_import, "x") }.to raise_error(ArgumentError, /unknown input_kind: "xml"/)
  end
end
