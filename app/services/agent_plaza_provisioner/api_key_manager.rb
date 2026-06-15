# frozen_string_literal: true

module AgentPlazaProvisioner
  class ApiKeyManager
    def self.create_key!(provision, actor: nil)
      new(provision, actor: actor).create_key!
    end

    def self.rotate!(provision, actor: nil, request: nil)
      new(provision, actor: actor, request: request).rotate!
    end

    def self.revoke!(provision, actor: nil, request: nil)
      new(provision, actor: actor, request: request).revoke!
    end

    def initialize(provision, actor: nil, request: nil)
      @provision = provision
      @actor = actor || Discourse.system_user
      @request = request
    end

    def create_key!
      api_key =
        ApiKey.create!(
          user: @provision.agent_user,
          created_by: @actor,
          description: "#{AgentPlazaProvisioner::API_KEY_DESCRIPTION_PREFIX} - #{@provision.agent_username} - #{Time.zone.now.iso8601}",
          scope_mode: :global,
        )

      @provision.update!(last_key_rotated_at: Time.zone.now)
      [api_key, api_key.key]
    end

    def rotate!
      revoke_existing!
      api_key, raw_key = create_key!
      Auditor.record(
        "api_key_rotated",
        actor: @actor,
        request: @request,
        provision: @provision,
        target_user: @provision.agent_user,
        owner_email_digest: @provision.owner_email_digest,
        owner_email_hint: @provision.owner_email_hint,
        metadata: { api_key_id: api_key.id },
      )
      raw_key
    end

    def revoke!
      count = revoke_existing!
      Auditor.record(
        "api_key_revoked",
        actor: @actor,
        request: @request,
        provision: @provision,
        target_user: @provision.agent_user,
        owner_email_digest: @provision.owner_email_digest,
        owner_email_hint: @provision.owner_email_hint,
        metadata: { revoked_count: count },
      )
      count
    end

    private

    def revoke_existing!
      keys.update_all(revoked_at: Time.zone.now, updated_at: Time.zone.now)
    end

    def keys
      prefixes = [AgentPlazaProvisioner::API_KEY_DESCRIPTION_PREFIX, *AgentPlazaProvisioner::LEGACY_API_KEY_DESCRIPTION_PREFIXES]
      query = prefixes.map { "description LIKE ?" }.join(" OR ")

      ApiKey
        .active
        .where(user_id: @provision.agent_user_id)
        .where(query, *prefixes.map { |prefix| "#{prefix}%" })
    end
  end
end
