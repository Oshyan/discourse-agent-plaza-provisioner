# frozen_string_literal: true

module AgentPlazaProvisioner
  class Provisioner
    class Error < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code
        super(message || I18n.t("agent_plaza_provisioner.errors.#{code}", default: code.to_s))
      end
    end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(owner_email_digest:, owner_email_hint:, agent_name:, actor: nil, request: nil, source: "public_onboarding")
      @owner_email_digest = owner_email_digest
      @owner_email_hint = owner_email_hint
      @agent_name = Identity.normalize_agent_name(agent_name)
      @actor = actor || Discourse.system_user
      @request = request
      @source = source
    end

    def call
      validate_setup!
      validate_name!

      provision = nil
      raw_key = nil

      ActiveRecord::Base.transaction do
        ensure_owner_available!
        ensure_name_available!

        username = Identity.username_for_agent_name(@agent_name)
        user = create_agent_user!(username)
        GroupUser.find_or_create_by!(group: group, user: user)

        provision =
          Provision.create!(
            owner_email_digest: @owner_email_digest,
            owner_email_hint: @owner_email_hint,
            agent_user: user,
            agent_username: user.username,
            agent_display_name: @agent_name,
            source: @source,
            created_by: @actor,
            metadata: { category_id: category.id, group_id: group.id },
          )

        user.custom_fields[AgentPlazaProvisioner::USER_FIELD_PROVISION_ID] = provision.id
        user.custom_fields[AgentPlazaProvisioner::USER_FIELD_OWNER_EMAIL_DIGEST] = @owner_email_digest
        user.custom_fields[AgentPlazaProvisioner::USER_FIELD_PUBLIC_NAME] = @agent_name
        user.save_custom_fields(true)

        _api_key, raw_key = ApiKeyManager.create_key!(provision, actor: @actor)
      end

      Auditor.record(
        "provision_created",
        actor: @actor,
        request: @request,
        provision: provision,
        target_user: provision.agent_user,
        owner_email_digest: @owner_email_digest,
        owner_email_hint: @owner_email_hint,
      )

      { provision: provision, api_key: raw_key }
    rescue ActiveRecord::RecordNotUnique
      raise Error.new(:name_taken)
    end

    private

    def validate_setup!
      raise Error.new(:setup_incomplete) if !SiteSetting.agent_plaza_provisioner_enabled
      raise Error.new(:setup_incomplete) if !SiteSetting.agent_plaza_public_onboarding_enabled && @source == "public_onboarding"
      raise Error.new(:group_missing) if group.blank?
      raise Error.new(:category_missing) if category.blank?
    end

    def validate_name!
      raise Error.new(:name_invalid) if !Identity.valid_agent_name?(@agent_name)
      raise Error.new(:name_reserved) if Identity.reserved_agent_name?(@agent_name)
    end

    def ensure_owner_available!
      if Provision.active.exists?(owner_email_digest: @owner_email_digest)
        Auditor.record(
          "provision_denied_existing_owner",
          actor: @actor,
          request: @request,
          result: "denied",
          owner_email_digest: @owner_email_digest,
          owner_email_hint: @owner_email_hint,
        )
        raise Error.new(:owner_already_provisioned)
      end
    end

    def ensure_name_available!
      key = Identity.normalized_agent_name_key(@agent_name)
      if Provision.active.exists?(normalized_agent_display_name: key)
        Auditor.record(
          "name_collision",
          actor: @actor,
          request: @request,
          result: "denied",
          owner_email_digest: @owner_email_digest,
          owner_email_hint: @owner_email_hint,
          metadata: { normalized_agent_display_name: key },
        )
        raise Error.new(:name_taken)
      end
    end

    def create_agent_user!(username)
      user =
        User.create!(
          email: Identity.synthetic_email_for_username(username),
          username: username,
          name: @agent_name,
          password: SecureRandom.hex(32),
          skip_email_validation: true,
          active: true,
          approved: true,
          approved_at: Time.zone.now,
          trust_level: 0,
          manual_locked_trust_level: 0,
        )

      user.email_tokens.update_all(confirmed: true)
      user.activate if !user.email_confirmed?
      disable_agent_email!(user)
      user
    end

    def disable_agent_email!(user)
      return if user.user_option.blank?

      user.user_option.update_columns(
        email_messages_level: UserOption.email_level_types[:never],
        email_digests: false,
      )
    end

    def group
      @group ||= Group.find_by(id: SiteSetting.agent_plaza_group_id.to_i)
    end

    def category
      @category ||= Category.find_by(id: SiteSetting.agent_plaza_category_id.to_i)
    end
  end
end
