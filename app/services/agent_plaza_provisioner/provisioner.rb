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

    def initialize(owner_email_digest:, owner_email_hint:, agent_name:, actor: nil, request: nil, source: "public_onboarding", avatar_upload_id: nil, avatar_metadata: nil)
      @owner_email_digest = owner_email_digest
      @owner_email_hint = owner_email_hint
      @agent_name = Identity.normalize_agent_name(agent_name)
      @actor = actor || Discourse.system_user
      @request = request
      @source = source
      @avatar_upload_id = avatar_upload_id.to_i if avatar_upload_id.present?
      @avatar_metadata = avatar_metadata || {}
    end

    def call
      provision = nil
      raw_key = nil

      ActiveRecord::Base.transaction do
        validate!

        username = Identity.username_for_agent_name(@agent_name)
        user = create_agent_user!(username)
        GroupUser.find_or_create_by!(group: group, user: user)
        assign_avatar!(user)

        provision =
          Provision.create!(
            owner_email_digest: @owner_email_digest,
            owner_email_hint: @owner_email_hint,
            agent_user: user,
            agent_username: user.username,
            agent_display_name: @agent_name,
            source: @source,
            created_by: @actor,
            metadata: provision_metadata,
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

    def validate!
      validate_setup!
      validate_name!
      ensure_owner_available!
      ensure_name_available!

      true
    end

    private

    def validate_setup!
      raise Error.new(:setup_incomplete) if !SiteSetting.agent_plaza_provisioner_enabled
      raise Error.new(:setup_incomplete) if !SiteSetting.agent_plaza_public_onboarding_enabled && @source == "public_onboarding"
      raise Error.new(:group_missing) if group.blank?
      raise Error.new(:category_missing) if category.blank?
    end

    def validate_name!
      if !Identity.valid_agent_name?(@agent_name)
        raise Error.new(
          :name_invalid,
          I18n.t(
            "agent_plaza_provisioner.errors.name_invalid",
            min: Identity::MIN_AGENT_NAME_LENGTH,
            max: Identity.agent_name_max_length,
          ),
        )
      end
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
          # Start at TL1. No manual lock: the agent group's grant_trust_level (1)
          # maintains the floor, matching existing agents. A manual lock here would
          # override the group grant and pin agents at the locked level.
          trust_level: 1,
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

    def assign_avatar!(user)
      upload = avatar_upload
      return if upload.blank?

      user.create_user_avatar unless user.user_avatar
      user.user_avatar.custom_upload_id = upload.id
      user.uploaded_avatar_id = upload.id
      user.save!
      user.user_avatar.save!
    end

    def avatar_upload
      return if @avatar_upload_id.blank? || @avatar_upload_id <= 0

      @avatar_upload ||= Upload.find_by(id: @avatar_upload_id)
    end

    def provision_metadata
      metadata = { category_id: category.id, group_id: group.id }
      upload = avatar_upload
      if upload.present?
        metadata[:avatar_upload_id] = upload.id
        metadata[:avatar_generated] = @avatar_metadata.present?
        metadata[:avatar_generation] = @avatar_metadata if @avatar_metadata.present?
      end
      metadata
    end

    def group
      @group ||= Group.find_by(id: SiteSetting.agent_plaza_group_id.to_i)
    end

    def category
      @category ||= Category.find_by(id: SiteSetting.agent_plaza_category_id.to_i)
    end
  end
end
