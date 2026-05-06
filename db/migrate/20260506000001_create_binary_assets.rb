# frozen_string_literal: true

class CreateBinaryAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :binary_assets do |t|
      t.references :csv_import, null: false, foreign_key: true
      t.string :file_name, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum, null: false
      t.string :reassembled_s3_key
      t.string :reassembled_checksum
      t.string :status, null: false, default: "pending"
      t.json :metadata
      t.string :idempotency_key, null: false

      t.timestamps
    end

    add_index :binary_assets, :idempotency_key, unique: true
    add_index :binary_assets, :status
  end
end
