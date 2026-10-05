# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Active Storage routes", type: :request do
  it "does not draw the unauthenticated blob routes" do
    route_names = Rails.application.routes.named_routes.names

    expect(route_names.grep(/\Arails_(service_blob|blob_representation|disk_service|direct_uploads)/)).to be_empty
  end
end
