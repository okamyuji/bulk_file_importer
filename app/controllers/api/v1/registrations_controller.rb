# typed: true
# frozen_string_literal: true

module Api
  module V1
    class RegistrationsController < Devise::RegistrationsController
      respond_to :json
      protect_from_forgery with: :null_session

      private

      def respond_with(resource, _opts = {})
        if resource.persisted?
          Current.user_id = resource.id
          AuditLogger.event("auth.sign_up", provider: "password")
          render json: {
                   user: {
                     id: resource.id,
                     email: resource.email,
                     name: resource.name,
                   },
                   token: request.env["warden-jwt_auth.token"],
                 },
                 status: :created
        else
          AuditLogger.event("auth.sign_up_failure", reasons: resource.errors.full_messages.first(3))
          render json: { error: "invalid", details: resource.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def sign_up_params
        params.expect(user: %i[email password password_confirmation name])
      end
    end
  end
end
