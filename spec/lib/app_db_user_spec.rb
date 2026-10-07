# typed: false
# frozen_string_literal: true

require "rails_helper"
require "rake"

# CREATE USER と GRANT は暗黙にコミットされ、トランザクションでは巻き戻らない。
RSpec.describe AppDbUser do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:username) { "spec_app_#{SecureRandom.hex(4)}" }
  let(:password) { SecureRandom.hex(16) }
  let(:env) { { "DATABASE_APP_USERNAME" => username, "DATABASE_APP_PASSWORD" => password } }
  let(:table) { "app_db_user_spec_items" }
  let(:databases) { described_class.configured_databases }
  let(:created_users) { [] }

  def connect_as(user, pass, database: connection.current_database)
    config = connection.pool.db_config.configuration_hash
    Mysql2::Client.new(host: config[:host], port: config[:port], username: user, password: pass, database: database)
  end

  def grant(**overrides)
    created_users << overrides.fetch(:env, env)["DATABASE_APP_USERNAME"]
    described_class.grant!(**{ env: env }.merge(overrides))
  end

  before do
    connection.execute("CREATE TABLE IF NOT EXISTS #{table} (id INT PRIMARY KEY, name VARCHAR(20))")
  end

  after do
    connection.execute("DROP TABLE IF EXISTS #{table}")
    created_users.compact.uniq.each { |user| connection.execute("DROP USER IF EXISTS #{connection.quote(user)}@'%'") }
  end

  describe ".configured_databases" do
    it "lists the four databases of the current environment" do
      expect(databases).to eq(%w[bulk_file_importer_test bulk_file_importer_test_cache bulk_file_importer_test_queue bulk_file_importer_test_cable])
    end
  end

  describe ".quote_database" do
    it "escapes the _ and % wildcards and the \\ escape character of GRANT database names" do
      expect(described_class.quote_database(connection, "a%b_c\\d")).to eq("`a\\%b\\_c\\\\d`")
    end
  end

  describe ".grant!" do
    it "lets the user read and write rows" do
      grant
      client = connect_as(username, password)

      client.query("INSERT INTO #{table} (id, name) VALUES (1, 'a')")
      client.query("UPDATE #{table} SET name = 'b' WHERE id = 1")
      expect(client.query("SELECT name FROM #{table}").to_a).to eq([ { "name" => "b" } ])
      client.query("DELETE FROM #{table} WHERE id = 1")
      expect(client.query("SELECT COUNT(*) AS n FROM #{table}").first["n"]).to eq(0)
    end

    it "denies CREATE TABLE and DROP TABLE" do
      grant
      client = connect_as(username, password)

      expect { client.query("CREATE TABLE app_db_user_spec_denied (id INT)") }.to raise_error(Mysql2::Error, /command denied/)
      expect { client.query("DROP TABLE #{table}") }.to raise_error(Mysql2::Error, /command denied/)
    end

    it "grants exactly SELECT, INSERT, UPDATE and DELETE on each configured database" do
      grant

      grants = connection.select_values("SHOW GRANTS FOR #{connection.quote(username)}@'%'")
      expect(grants).to contain_exactly(
        "GRANT USAGE ON *.* TO `#{username}`@`%`",
        *%w[test test\\_cache test\\_queue test\\_cable].map { |suffix| "GRANT SELECT, INSERT, UPDATE, DELETE ON `bulk\\_file\\_importer\\_#{suffix}`.* TO `#{username}`@`%`" }
      )
    end

    it "does not let the user reach a database whose name matches the others only through the _ wildcard" do
      lookalike = "bulk_file_importer_testXcache"
      connection.execute("CREATE DATABASE IF NOT EXISTS #{lookalike}")
      grant

      expect { connect_as(username, password, database: lookalike) }.to raise_error(Mysql2::Error, /Access denied/)
    ensure
      connection.execute("DROP DATABASE IF EXISTS #{lookalike}")
    end

    it "lets the user reach every configured database" do
      grant

      databases.each do |db|
        expect(connect_as(username, password, database: db).query("SELECT 1 AS one").first["one"]).to eq(1)
      end
    end

    it "succeeds when run twice with the same password" do
      grant
      expect { grant }.not_to raise_error
      expect(connect_as(username, password).query("SELECT 1 AS one").first["one"]).to eq(1)
    end

    it "switches to the new password on a second run" do
      grant
      new_password = SecureRandom.hex(16)
      grant(env: env.merge("DATABASE_APP_PASSWORD" => new_password))

      expect(connect_as(username, new_password).query("SELECT 1 AS one").first["one"]).to eq(1)
      expect { connect_as(username, password) }.to raise_error(Mysql2::Error, /Access denied/)
    end

    it "quotes a user name and password that contain quotes and backslashes" do
      tricky_user = "spec_q'#{SecureRandom.hex(2)}\\"
      tricky_password = "#{SecureRandom.hex(8)}'\"\\;"
      tricky_env = { "DATABASE_APP_USERNAME" => tricky_user, "DATABASE_APP_PASSWORD" => tricky_password }

      grant(env: tricky_env)

      expect(connect_as(tricky_user, tricky_password).query("SELECT 1 AS one").first["one"]).to eq(1)
    end

    it "accepts a 32-character user name, the MySQL maximum" do
      long_user = "u#{SecureRandom.hex(16)[0, 31]}"
      grant(env: env.merge("DATABASE_APP_USERNAME" => long_user))

      expect(connect_as(long_user, password).query("SELECT 1 AS one").first["one"]).to eq(1)
    end

    it "raises AppDbUser::Error without a cause when MySQL rejects a 33-character user name" do
      too_long_user = "u#{SecureRandom.hex(16)}"

      expect { described_class.grant!(env: env.merge("DATABASE_APP_USERNAME" => too_long_user)) }
        .to raise_error(described_class::Error, /too long for user name/) { |error|
          expect(error.cause).to be_nil
          expect(error.message).not_to include(password)
        }
    end

    it "masks the raw and the escaped password when MySQL quotes the statement" do
      quoted_password = "#{SecureRandom.hex(8)}'x"
      escaped = connection.quote(quoted_password)[1..-2]
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute).with(/\ACREATE USER/)
        .and_raise(ActiveRecord::StatementInvalid, "near '#{escaped}' and '#{quoted_password}'")

      expect { described_class.grant!(env: env.merge("DATABASE_APP_PASSWORD" => quoted_password)) }
        .to raise_error(described_class::Error, "near '[FILTERED]' and '[FILTERED]'")
    end

    it "does not log the password" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      logger.level = Logger::DEBUG
      allow(ActiveRecord::Base).to receive(:logger).and_return(logger)

      grant

      expect(io.string).not_to include(password)
    end

    %w[DATABASE_APP_USERNAME DATABASE_APP_PASSWORD].each do |key|
      it "raises when #{key} is missing" do
        expect { described_class.grant!(env: env.except(key)) }
          .to raise_error(described_class::Error, "#{key} is not set")
      end

      it "raises when #{key} is blank" do
        expect { described_class.grant!(env: env.merge(key => "  ")) }
          .to raise_error(described_class::Error, "#{key} is not set")
      end
    end

    it "refuses to change the password of the connecting user" do
      current_user = connection.select_value("SELECT CURRENT_USER()").rpartition("@").first
      allow(connection).to receive(:execute).and_call_original

      expect { described_class.grant!(env: env.merge("DATABASE_APP_USERNAME" => current_user)) }
        .to raise_error(described_class::Error, /must differ from the connecting user/)
      expect(connection).not_to have_received(:execute).with(/USER/)
    end
  end

  describe "db:grant_app_user" do
    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("db:grant_app_user")
      Rake::Task["db:grant_app_user"].reenable
    end

    it "grants the user named in the environment" do
      created_users << username
      stub_const("ENV", ENV.to_h.merge(env))

      expect { Rake::Task["db:grant_app_user"].invoke }.to output(/Granted SELECT, INSERT, UPDATE, DELETE on bulk_file_importer_test/).to_stdout
      expect(connect_as(username, password).query("SELECT 1 AS one").first["one"]).to eq(1)
    end

    it "fails with a clear message when the environment is missing" do
      stub_const("ENV", ENV.to_h.except("DATABASE_APP_USERNAME", "DATABASE_APP_PASSWORD"))

      expect { Rake::Task["db:grant_app_user"].invoke }.to raise_error(AppDbUser::Error, "DATABASE_APP_USERNAME is not set")
    end
  end
end
