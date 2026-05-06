# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_06_000001) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "binary_assets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "csv_import_id", null: false
    t.string "file_name", null: false
    t.string "idempotency_key", null: false
    t.json "metadata"
    t.string "reassembled_checksum"
    t.string "reassembled_s3_key"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["csv_import_id"], name: "index_binary_assets_on_csv_import_id"
    t.index ["idempotency_key"], name: "index_binary_assets_on_idempotency_key", unique: true
    t.index ["status"], name: "index_binary_assets_on_status"
  end

  create_table "csv_import_chunks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "byte_size", default: 0, null: false
    t.string "checksum"
    t.integer "chunk_index", null: false
    t.datetime "created_at", null: false
    t.bigint "csv_import_id", null: false
    t.bigint "end_byte"
    t.integer "end_row"
    t.json "error_details"
    t.integer "failed_rows", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "processed_rows", default: 0, null: false
    t.integer "retry_count", default: 0, null: false
    t.string "s3_key", null: false
    t.bigint "start_byte"
    t.integer "start_row"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["csv_import_id", "chunk_index"], name: "index_csv_import_chunks_on_csv_import_id_and_chunk_index", unique: true
    t.index ["csv_import_id"], name: "index_csv_import_chunks_on_csv_import_id"
    t.index ["status"], name: "index_csv_import_chunks_on_status"
  end

  create_table "csv_imports", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "byte_size", default: 0, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "failed_bytes", default: 0, null: false
    t.integer "failed_rows", default: 0, null: false
    t.string "file_name", null: false
    t.string "idempotency_key", null: false
    t.string "input_kind", default: "csv", null: false
    t.bigint "processed_bytes", default: 0, null: false
    t.integer "processed_rows", default: 0, null: false
    t.string "reassembled_checksum"
    t.string "reassembled_s3_key"
    t.integer "remaining_chunks", default: 0, null: false
    t.string "s3_prefix"
    t.string "source_checksum"
    t.string "status", default: "pending", null: false
    t.string "target_kind", null: false
    t.bigint "total_bytes", default: 0, null: false
    t.integer "total_chunks", default: 0, null: false
    t.integer "total_rows", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["idempotency_key"], name: "index_csv_imports_on_idempotency_key", unique: true
    t.index ["input_kind"], name: "index_csv_imports_on_input_kind"
    t.index ["status"], name: "index_csv_imports_on_status"
    t.index ["user_id", "created_at"], name: "index_csv_imports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_csv_imports_on_user_id"
  end

  create_table "jwt_denylists", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "exp"
    t.string "jti"
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti", unique: true
  end

  create_table "ledger_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "account_code", limit: 16, null: false
    t.datetime "created_at", null: false
    t.decimal "credit", precision: 14, scale: 2, default: "0.0", null: false
    t.bigint "csv_import_id", null: false
    t.decimal "debit", precision: 14, scale: 2, default: "0.0", null: false
    t.string "description"
    t.string "idempotency_key", null: false
    t.date "posted_on", null: false
    t.datetime "updated_at", null: false
    t.index ["csv_import_id"], name: "index_ledger_entries_on_csv_import_id"
    t.index ["idempotency_key"], name: "index_ledger_entries_on_idempotency_key", unique: true
    t.index ["posted_on", "account_code"], name: "index_ledger_entries_on_posted_on_and_account_code"
  end

  create_table "sales_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "csv_import_id", null: false
    t.string "customer_code", limit: 32, null: false
    t.string "idempotency_key", null: false
    t.string "memo"
    t.string "product_code", limit: 32, null: false
    t.integer "quantity", null: false
    t.date "recorded_on", null: false
    t.decimal "unit_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["csv_import_id"], name: "index_sales_records_on_csv_import_id"
    t.index ["idempotency_key"], name: "index_sales_records_on_idempotency_key", unique: true
    t.index ["recorded_on", "customer_code"], name: "index_sales_records_on_recorded_on_and_customer_code"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "binary_assets", "csv_imports"
  add_foreign_key "csv_import_chunks", "csv_imports"
  add_foreign_key "csv_imports", "users"
  add_foreign_key "ledger_entries", "csv_imports"
  add_foreign_key "sales_records", "csv_imports"
end
