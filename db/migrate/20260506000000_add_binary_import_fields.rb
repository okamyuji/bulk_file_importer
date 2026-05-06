# frozen_string_literal: true

class AddBinaryImportFields < ActiveRecord::Migration[8.1]
  def change
    change_table :csv_imports, bulk: true do |t|
      t.string :input_kind, null: false, default: "csv"
      t.string :content_type
      t.bigint :byte_size, null: false, default: 0
      t.bigint :total_bytes, null: false, default: 0
      t.bigint :processed_bytes, null: false, default: 0
      t.bigint :failed_bytes, null: false, default: 0
      t.string :reassembled_s3_key
      t.string :source_checksum
      t.string :reassembled_checksum
    end

    change_table :csv_import_chunks, bulk: true do |t|
      t.change_null :start_row, true
      t.change_null :end_row, true
      t.bigint :start_byte
      t.bigint :end_byte
      t.bigint :byte_size, null: false, default: 0
      t.string :checksum
    end

    add_index :csv_imports, :input_kind
  end
end
