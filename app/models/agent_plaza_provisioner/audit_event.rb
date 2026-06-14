# frozen_string_literal: true

module AgentPlazaProvisioner
  class AuditEvent < ActiveRecord::Base
    self.table_name = "agent_plaza_audit_events"

    RESULTS = %w[ok denied failed].freeze

    belongs_to :actor_user, class_name: "::User", optional: true
    belongs_to :provision, class_name: "AgentPlazaProvisioner::Provision", optional: true
    belongs_to :target_user, class_name: "::User", optional: true
    belongs_to :reviewed_by, class_name: "::User", foreign_key: :reviewed_by_user_id, optional: true

    validates :action, presence: true
    validates :actor_type, presence: true
    validates :result, inclusion: { in: RESULTS }

    before_validation :normalize_fields

    scope :recent, -> { order(created_at: :desc) }

    def mark_reviewed!(user)
      update!(reviewed_at: Time.zone.now, reviewed_by: user)
    end

    private

    def normalize_fields
      self.action = action.to_s.strip.presence
      self.actor_type = actor_type.to_s.strip.presence || "system"
      self.result = result.to_s.presence || "ok"
      self.user_agent = user_agent.to_s.truncate(500).presence
      self.metadata = (metadata || {}).as_json
      self.created_at ||= Time.zone.now
    end
  end
end
