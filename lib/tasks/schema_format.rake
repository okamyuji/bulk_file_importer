# typed: false
# frozen_string_literal: true

# db:schema:dump（db:migrate等からも呼ばれる）はRailsネイティブ形式で
# db/schema.rbを書き出すため、lefthookのstreeフォーマットチェックと衝突する。
# dump直後にstreeで整形し、フォーマット差分が作業ツリーに残らないようにする。
if Rake::Task.task_defined?("db:schema:dump")
  Rake::Task["db:schema:dump"].enhance do
    schema = Rails.root.join("db", "schema.rb")
    system("bundle", "exec", "stree", "write", schema.to_s, exception: true) if schema.exist?
  end
end
