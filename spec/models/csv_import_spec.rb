# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImport do
  describe "validations" do
    it { is_expected.to validate_presence_of(:file_name) }
    it { is_expected.to validate_inclusion_of(:input_kind).in_array(CsvImport::INPUT_KINDS) }
    it { is_expected.to validate_inclusion_of(:target_kind).in_array(CsvImport::TARGET_KINDS) }
    it { is_expected.to validate_inclusion_of(:status).in_array(CsvImport::STATUSES) }

    it "enforces unique idempotency_key at the DB level" do
      create(:csv_import, idempotency_key: "same")
      expect { create(:csv_import, idempotency_key: "same") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects a binary target for CSV imports" do
      csv_import = build(:csv_import, input_kind: "csv", target_kind: "binary_asset")
      expect(csv_import).not_to be_valid
      expect(csv_import.errors[:target_kind]).to be_present
    end

    it "accepts the binary target for binary imports" do
      csv_import = build(:csv_import, input_kind: "binary", target_kind: "binary_asset")
      expect(csv_import).to be_valid
    end
  end

  describe "#completed?" do
    it "returns true for terminal statuses" do
      %w[completed completed_with_errors partially_failed failed].each do |s|
        expect(build(:csv_import, status: s)).to be_completed
      end
    end

    it "returns false for in-progress statuses" do
      %w[pending splitting processing].each { |s| expect(build(:csv_import, status: s)).not_to be_completed }
    end
  end
end
