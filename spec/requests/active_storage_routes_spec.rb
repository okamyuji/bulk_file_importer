# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Active Storage routes", type: :request do
  it "does not draw the unauthenticated blob routes" do
    # named_routes は eager_load 無効時に再描画されないため、routes.routes から読む。
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    expect(paths.select { |path| path.start_with?(ActiveStorage.routes_prefix) }).to be_empty
  end
end
