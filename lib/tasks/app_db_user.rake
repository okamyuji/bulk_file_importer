# typed: false
# frozen_string_literal: true

namespace :db do
  desc "Create or update the DML-only MySQL user from DATABASE_APP_USERNAME and DATABASE_APP_PASSWORD"
  task grant_app_user: :environment do
    AppDbUser.grant!
    puts "Granted #{AppDbUser::PRIVILEGES} on #{AppDbUser.configured_databases.join(", ")}"
  end
end
