# typed: true
# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include AuthorizationErrorHandling

  allow_browser versions: :modern

  before_action :set_audit_context

  private

  def set_audit_context
    Current.request_id = request.request_id
    Current.user_id = (respond_to?(:current_user, true) && current_user&.id) || nil
  end
end
