# frozen_string_literal: true

class CreateAgentPlazaEmailChallenges < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_plaza_email_challenges do |t|
      t.text :email_digest, null: false
      t.text :email_hint
      t.text :code_digest, null: false
      t.text :status, null: false, default: "pending"
      t.integer :attempts_count, null: false, default: 0
      t.inet :ip_address
      t.text :user_agent
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :reviewed_at
      t.bigint :reviewed_by_user_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps null: false
    end

    add_index :agent_plaza_email_challenges,
              %i[email_digest created_at],
              name: "idx_ap_challenges_email_created"
    add_index :agent_plaza_email_challenges, %i[ip_address created_at], name: "idx_ap_challenges_ip_created"
    add_index :agent_plaza_email_challenges, :expires_at, name: "idx_ap_challenges_expires"
    add_index :agent_plaza_email_challenges,
              :email_digest,
              name: "idx_ap_challenges_pending",
              where: "status = 'pending'"
  end
end
