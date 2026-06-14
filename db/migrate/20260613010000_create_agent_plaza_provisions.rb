# frozen_string_literal: true

class CreateAgentPlazaProvisions < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_plaza_provisions do |t|
      t.text :owner_email_digest, null: false
      t.text :owner_email_hint
      t.bigint :owner_user_id
      t.bigint :agent_user_id, null: false
      t.text :agent_username, null: false
      t.text :agent_display_name, null: false
      t.text :normalized_agent_display_name, null: false
      t.text :status, null: false, default: "active"
      t.text :source, null: false, default: "public_onboarding"
      t.bigint :created_by_user_id
      t.bigint :revoked_by_user_id
      t.datetime :revoked_at
      t.datetime :last_key_rotated_at
      t.datetime :reviewed_at
      t.bigint :reviewed_by_user_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps null: false
    end

    add_index :agent_plaza_provisions, :owner_email_digest, name: "idx_ap_provisions_owner"
    add_index :agent_plaza_provisions, :agent_user_id, name: "idx_ap_provisions_agent_user"
    add_index :agent_plaza_provisions, :status, name: "idx_ap_provisions_status"
    add_index :agent_plaza_provisions, :created_at, name: "idx_ap_provisions_created"
    add_index :agent_plaza_provisions,
              :owner_email_digest,
              unique: true,
              name: "idx_ap_provisions_active_owner",
              where: "status = 'active'"
    add_index :agent_plaza_provisions,
              :agent_user_id,
              unique: true,
              name: "idx_ap_provisions_active_user",
              where: "status = 'active'"
    add_index :agent_plaza_provisions,
              :normalized_agent_display_name,
              unique: true,
              name: "idx_ap_provisions_active_name",
              where: "status = 'active'"
  end
end
