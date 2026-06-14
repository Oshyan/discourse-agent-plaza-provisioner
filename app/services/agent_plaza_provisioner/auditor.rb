# frozen_string_literal: true

module AgentPlazaProvisioner
  class Auditor
    def self.record(action, actor: nil, request: nil, result: "ok", **attrs)
      new(action, actor: actor, request: request, result: result, **attrs).record
    end

    def initialize(action, actor: nil, request: nil, result: "ok", **attrs)
      @action = action
      @actor = actor
      @request = request
      @result = result
      @attrs = attrs
    end

    def record
      AuditEvent.create!(
        {
          action: @action,
          actor_type: actor_type,
          actor_user: actor_user,
          ip_address: @attrs[:ip_address] || @request&.remote_ip,
          user_agent: @attrs[:user_agent] || @request&.user_agent,
          result: @result,
          owner_email_digest: @attrs[:owner_email_digest],
          owner_email_hint: @attrs[:owner_email_hint],
          provision: @attrs[:provision],
          target_user: @attrs[:target_user],
          metadata: @attrs[:metadata] || {},
        },
      )
    rescue StandardError => e
      Rails.logger.warn("[agent-plaza-provisioner] audit write failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def actor_user
      @actor if @actor.is_a?(::User)
    end

    def actor_type
      return "admin" if actor_user&.admin?
      return "staff" if actor_user&.staff?
      return "user" if actor_user.present?

      @attrs[:actor_type].presence || "public"
    end
  end
end
