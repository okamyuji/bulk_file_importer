# frozen_string_literal: true

require "rails_helper"
require "base64"

RSpec.describe "Api::V1::CsvImports", type: :request do
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

  def auth_headers(user)
    post "/api/v1/sessions",
         params: { user: { email: user.email, password: user.password } }.to_json,
         headers: {
           "Content-Type" => "application/json",
         }
    { "Authorization" => response.headers["Authorization"] }
  end

  describe "GET /api/v1/csv_imports" do
    it "requires authentication" do
      get "/api/v1/csv_imports"
      expect(response).to have_http_status(:unauthorized)
    end

    it "only returns the current user's imports" do
      create(:csv_import, user: alice, file_name: "mine.csv")
      create(:csv_import, user: bob, file_name: "theirs.csv")

      get "/api/v1/csv_imports", headers: auth_headers(alice)
      expect(response).to have_http_status(:ok)
      files = JSON.parse(response.body)["data"].pluck("file_name")
      expect(files).to contain_exactly("mine.csv")
    end
  end

  describe "GET /api/v1/csv_imports/:id" do
    it "returns 403 when another user requests it" do
      imp = create(:csv_import, user: alice)
      get "/api/v1/csv_imports/#{imp.id}", headers: auth_headers(bob)
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("forbidden")
    end
  end

  describe "POST /api/v1/csv_imports" do
    let(:file) do
      fixture = Rails.root.join("tmp/spec_sample.csv")
      File.write(
        fixture,
        "recorded_on,customer_code,product_code,quantity,unit_price,amount,memo\n2026-04-01,C1,P1,1,1,1,ok\n",
      )
      Rack::Test::UploadedFile.new(fixture.to_s, "text/csv")
    end
    let(:png_file) do
      fixture = Rails.root.join("tmp/spec_sample.png")
      File.binwrite(
        fixture,
        Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="),
      )
      Rack::Test::UploadedFile.new(fixture.to_s, "image/png")
    end

    it "creates an import and enqueues CsvImportJob" do
      expect {
        post "/api/v1/csv_imports",
             params: {
               file: file,
               target_kind: "sales_record",
               input_kind: "csv",
             },
             headers: auth_headers(alice)
      }.to have_enqueued_job(CsvImportJob)
      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body).dig("data", "status")).to eq("pending")
    end

    it "accepts a supported binary image import" do
      expect {
        post "/api/v1/csv_imports",
             params: {
               file: png_file,
               target_kind: "binary_asset",
               input_kind: "binary",
             },
             headers: auth_headers(alice)
      }.to have_enqueued_job(CsvImportJob)
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body).fetch("data")
      expect(body["input_kind"]).to eq("binary")
      expect(body["content_type"]).to eq("image/png")
      expect(body["source_checksum"]).to be_present
    end

    it "rejects invalid target_kind" do
      post "/api/v1/csv_imports", params: { file: file, target_kind: "nope" }, headers: auth_headers(alice)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a binary file requested as CSV" do
      post "/api/v1/csv_imports",
           params: {
             file: png_file,
             target_kind: "sales_record",
             input_kind: "csv",
           },
           headers: auth_headers(alice)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/csv_imports/:id/retry" do
    it "forbids non-owner" do
      imp = create(:csv_import, user: alice)
      post "/api/v1/csv_imports/#{imp.id}/retry", headers: auth_headers(bob)
      expect(response).to have_http_status(:forbidden)
    end

    it "allows the owner even when there are no failed chunks" do
      imp = create(:csv_import, user: alice)
      post "/api/v1/csv_imports/#{imp.id}/retry", headers: auth_headers(alice)
      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["retried"]).to eq(0)
    end
  end
end
