# typed: true
# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    include Pundit::Authorization
    include AuthorizationErrorHandling
    include ActionController::Cookies

    before_action :authenticate_user!
    before_action :set_audit_context

    respond_to :json

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not_found" }, status: :not_found
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render json: { error: "invalid", details: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def set_audit_context
      Current.request_id = request.request_id
      Current.user_id = current_user&.id
    end
  end
end
