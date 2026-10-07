# typed: false
# frozen_string_literal: true

# web と worker が接続する DML 専用の MySQL ユーザーを作り、パスワードと権限を揃える。
# DDL 権限を持つユーザー（本番では Aurora のマスター）で接続して呼ぶ。
module AppDbUser
  class Error < StandardError; end

  PRIVILEGES = "SELECT, INSERT, UPDATE, DELETE"

  module_function

  def grant!(env: ENV, connection: ActiveRecord::Base.connection, databases: configured_databases)
    username = fetch!(env, "DATABASE_APP_USERNAME")
    password = fetch!(env, "DATABASE_APP_PASSWORD")
    current_user = connection.select_value("SELECT CURRENT_USER()").rpartition("@").first
    raise Error, "DATABASE_APP_USERNAME must differ from the connecting user" if username == current_user

    account = "#{connection.quote(username)}@'%'"
    statements = [
      "CREATE USER IF NOT EXISTS #{account} IDENTIFIED BY #{connection.quote(password)}",
      "ALTER USER #{account} IDENTIFIED BY #{connection.quote(password)}",
      *databases.map { |db| "GRANT #{PRIVILEGES} ON #{quote_database(connection, db)}.* TO #{account}" }
    ]
    statements.each { |sql| execute_redacted(connection, sql, password) }
  end

  def configured_databases
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).map(&:database)
  end

  # GRANT の DB 名では _ と % がワイルドカード、\ がエスケープ文字になり、似た名前の別 DB にも権限が及ぶ。
  def quote_database(connection, db)
    connection.quote_table_name(db.gsub(/[\\_%]/) { |c| "\\#{c}" })
  end

  def fetch!(env, key)
    value = env[key].to_s
    raise Error, "#{key} is not set" if value.strip.empty?

    value
  end

  # SQL ログと StatementInvalid#sql は SQL 全文を持つ。cause に繋ぐと例外の報告にパスワードが載る。
  # MySQL のエラー文も構文エラーでは文の一部を引用するため、値を伏せる。
  def execute_redacted(connection, sql, password)
    ActiveRecord::Base.logger.silence { connection.execute(sql) }
  rescue ActiveRecord::StatementInvalid => e
    secrets = [ connection.quote(password)[1..-2], password ]
    raise Error, secrets.reduce(e.message) { |message, secret| message.gsub(secret, "[FILTERED]") }, cause: nil
  end
end
