# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Registrations", type: :request do
  describe "POST /api/v1/registrations" do
    it "creates a user and returns a bearer token without relying on session cookies" do
      post "/api/v1/registrations",
           params: {
             user: {
               email: "new-user@example.com",
               password: "password",
               password_confirmation: "password",
               name: "New User",
             },
           }.to_json,
           headers: {
             "Content-Type" => "application/json",
             "Origin" => "http://localhost:5173",
           }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("user", "email")).to eq("new-user@example.com")
      expect(body["token"]).to be_present
      expect(response.headers["Authorization"]).to match(/\ABearer /)
      expect(response.headers["Set-Cookie"]).to be_blank
    end

    it "returns validation errors" do
      post "/api/v1/registrations",
           params: { user: { email: "", password: "password", password_confirmation: "password", name: "" } }.to_json,
           headers: {
             "Content-Type" => "application/json",
           }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("invalid")
    end
  end
end
