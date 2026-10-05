# typed: false
# ActionController::Base と ::API の両方に include するため、Sorbet は rescue_from/render の受け手を型付けできない。
# frozen_string_literal: true

module AuthorizationErrorHandling
  extend ActiveSupport::Concern

  included { rescue_from Pundit::NotAuthorizedError, with: :render_forbidden }

  private

  def render_forbidden(exception)
    AuditLogger.event(
      "authz.forbidden",
      policy: exception.policy.class.name,
      query: exception.query,
      target_type: exception.record.class.name,
      target_id: exception.record.respond_to?(:id) ? exception.record.id : nil,
    )
    render json: { error: "forbidden" }, status: :forbidden
  end
end
