# typed: true
# frozen_string_literal: true

module Api
  module V1
    class RegistrationsController < ActionController::API
      before_action :set_audit_context

      def create
        user = User.new(sign_up_params)

        if user.save
          Current.user_id = user.id
          AuditLogger.event("auth.sign_up", provider: "password")
          token = issue_token(user)
          response.set_header("Authorization", "Bearer #{token}")
          render json: { user: { id: user.id, email: user.email, name: user.name }, token: token }, status: :created
        else
          AuditLogger.event("auth.sign_up_failure", reasons: user.errors.full_messages.first(3))
          render json: { error: "invalid", details: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def issue_token(user)
        Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
      end

      def set_audit_context
        Current.request_id = request.request_id
      end

      def sign_up_params
        params.expect(user: %i[email password password_confirmation name])
      end
    end
  end
end
