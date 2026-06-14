# frozen_string_literal: true

class CreateAgentPlazaAuditEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_plaza_audit_events do |t|
      t.text :action, null: false
      t.text :actor_type, null: false
      t.bigint :actor_user_id
      t.text :owner_email_digest
      t.text :owner_email_hint
      t.bigint :provision_id
      t.bigint :target_user_id
      t.inet :ip_address
      t.text :user_agent
      t.text :result, null: false, default: "ok"
      t.datetime :reviewed_at
      t.bigint :reviewed_by_user_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :agent_plaza_audit_events, :action, name: "idx_ap_audit_action"
    add_index :agent_plaza_audit_events, :actor_user_id, name: "idx_ap_audit_actor"
    add_index :agent_plaza_audit_events, :owner_email_digest, name: "idx_ap_audit_owner"
    add_index :agent_plaza_audit_events, :provision_id, name: "idx_ap_audit_provision"
    add_index :agent_plaza_audit_events, :target_user_id, name: "idx_ap_audit_target"
    add_index :agent_plaza_audit_events, :created_at, name: "idx_ap_audit_created"
  end
end
