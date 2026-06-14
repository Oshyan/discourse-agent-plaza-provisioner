# frozen_string_literal: true

module AgentPlazaProvisioner
  module Admin
    class OverviewController < ::Admin::AdminController
      requires_plugin AgentPlazaProvisioner::PLUGIN_NAME

      SETTINGS_GROUPS = [
        {
          key: "onboarding",
          label: "Onboarding",
          description: "Public onboarding availability and verification limits.",
          fields: [
            { name: :agent_plaza_provisioner_enabled, label: "Enable provisioner", type: :boolean },
            { name: :agent_plaza_public_onboarding_enabled, label: "Public onboarding", type: :boolean },
            { name: :agent_plaza_allowlist_emails, label: "Allowlist emails", type: :list },
            { name: :agent_plaza_otp_expiry_minutes, label: "OTP expiry", type: :integer, suffix: "minutes" },
            { name: :agent_plaza_max_otp_attempts, label: "Max OTP attempts", type: :integer },
            { name: :agent_plaza_email_cooldown_minutes, label: "Email cooldown", type: :integer, suffix: "minutes" },
            { name: :agent_plaza_ip_hourly_limit, label: "IP hourly limit", type: :integer },
          ],
        },
        {
          key: "targets",
          label: "Discourse Targets",
          description: "The category and group used for provisioned agent users.",
          fields: [
            { name: :agent_plaza_category_id, label: "Agent Plaza category", type: :category },
            { name: :agent_plaza_category_url, label: "Agent Plaza URL", type: :string },
            { name: :agent_plaza_group_id, label: "Agent Plaza group ID", type: :integer },
          ],
        },
        {
          key: "identity",
          label: "Identity",
          description: "Username generation, synthetic email addresses, and reserved names.",
          fields: [
            { name: :agent_plaza_username_prefix, label: "Username prefix", type: :string },
            { name: :agent_plaza_synthetic_email_domain, label: "Synthetic email domain", type: :string },
            { name: :agent_plaza_reserved_agent_names, label: "Reserved agent names", type: :list },
          ],
        },
        {
          key: "avatars",
          label: "AI Avatars",
          description: "Optional avatar generation through existing Discourse AI image-generation tools.",
          fields: [
            { name: :agent_plaza_ai_avatars_enabled, label: "Enable AI avatars", type: :boolean },
            { name: :agent_plaza_ai_avatar_generation_tool_id, label: "Image-generation tool ID", type: :integer },
            { name: :agent_plaza_ai_avatar_size, label: "Requested image size", type: :string },
            { name: :agent_plaza_ai_avatar_prompt_template, label: "Avatar prompt template", type: :text_area },
          ],
        },
        {
          key: "readiness",
          label: "Readiness Checks",
          description: "Optional warnings for native Discourse features used by Agent Plaza agents.",
          fields: [
            { name: :agent_plaza_require_topic_voting_ready, label: "Require topic voting readiness", type: :boolean },
            { name: :agent_plaza_require_nested_replies_ready, label: "Require nested replies readiness", type: :boolean },
          ],
        },
      ].freeze

      SETTINGS_BY_NAME =
        SETTINGS_GROUPS
          .flat_map { |group| group[:fields] }
          .index_by { |field| field[:name].to_s }
          .freeze

      def show
        render_json_dump(
          stats: stats,
          readiness: readiness,
          provisions: serialize_provisions(Provision.recent.includes(:agent_user).limit(500)),
          challenges: serialize_challenges(EmailChallenge.recent.limit(500)),
          audit_events: serialize_audit_events(AuditEvent.recent.includes(:actor_user, :target_user).limit(1000)),
          settings: settings_summary,
          categories: categories,
          groups: groups.map { |group| serialize_group(group) },
        )
      end

      def update_setting
        field = setting_field_from_params!
        value = normalize_setting_value(field, params[:value])
        SiteSetting.set_and_log(field[:name], value, current_user)
        Auditor.record("settings_changed", actor: current_user, request: request, metadata: { setting: field[:name] })
        render_json_dump(success: true, settings: settings_summary, readiness: readiness)
      rescue Discourse::InvalidParameters, ArgumentError => e
        render_json_error e.message, status: 422
      end

      def reset_setting
        field = setting_field_from_params!
        SiteSetting.remove_override!(field[:name])
        Auditor.record("settings_changed", actor: current_user, request: request, metadata: { setting: field[:name], reset: true })
        render_json_dump(success: true, settings: settings_summary, readiness: readiness)
      rescue Discourse::InvalidParameters, ArgumentError => e
        render_json_error e.message, status: 422
      end

      def bulk_provisions
        provisions = provisions_from_params
        rotated_keys = []

        Provision.transaction do
          case params[:bulk_action].to_s
          when "rotate_keys"
            rotated_keys =
              provisions.map do |provision|
                raw_key = ApiKeyManager.rotate!(provision, actor: current_user, request: request)
                {
                  provision_id: provision.id,
                  agent_username: provision.agent_username,
                  agent_display_name: provision.agent_display_name,
                  api_key: raw_key,
                  onboarding_block: provision.reload.onboarding_block(api_key: raw_key),
                }
              end
          when "revoke_keys"
            provisions.each { |provision| ApiKeyManager.revoke!(provision, actor: current_user, request: request) }
          when "suspend"
            provisions.each { |provision| suspend_agent!(provision) }
          when "unsuspend"
            provisions.each { |provision| unsuspend_agent!(provision) }
          when "remove_group"
            provisions.each { |provision| GroupUser.where(group: target_group, user_id: provision.agent_user_id).destroy_all }
          when "add_group"
            provisions.each { |provision| GroupUser.find_or_create_by!(group: target_group, user_id: provision.agent_user_id) }
          when "revoke_provision"
            provisions.each { |provision| revoke_provision!(provision) }
          when "mark_reviewed"
            provisions.each { |provision| provision.mark_reviewed!(current_user) }
          else
            raise Discourse::InvalidParameters.new(:bulk_action)
          end
        end

        Auditor.record(
          "bulk_action_completed",
          actor: current_user,
          request: request,
          metadata: { table: "provisions", action: params[:bulk_action], count: provisions.size },
        )

        render_json_dump(success: true, provisions: serialize_provisions(Provision.recent.includes(:agent_user).limit(500)), rotated_keys: rotated_keys)
      rescue Discourse::InvalidParameters, ActiveRecord::RecordInvalid, Provisioner::Error => e
        Auditor.record(
          "bulk_action_failed",
          actor: current_user,
          request: request,
          result: "failed",
          metadata: { table: "provisions", action: params[:bulk_action], error: e.message },
        )
        render_json_error e.message, status: 422
      end

      def bulk_challenges
        challenges = EmailChallenge.where(id: Array(params[:challenge_ids]).map(&:to_i).select(&:positive?))
        raise Discourse::InvalidParameters.new(:challenge_ids) if challenges.blank?

        case params[:bulk_action].to_s
        when "expire"
          challenges.update_all(status: "expired", updated_at: Time.zone.now)
        when "mark_reviewed"
          challenges.find_each { |challenge| challenge.mark_reviewed!(current_user) }
        else
          raise Discourse::InvalidParameters.new(:bulk_action)
        end

        Auditor.record(
          "bulk_action_completed",
          actor: current_user,
          request: request,
          metadata: { table: "challenges", action: params[:bulk_action], count: challenges.size },
        )

        render_json_dump(success: true, challenges: serialize_challenges(EmailChallenge.recent.limit(500)))
      rescue Discourse::InvalidParameters => e
        render_json_error e.message, status: 422
      end

      def bulk_audit_events
        events = AuditEvent.where(id: Array(params[:audit_event_ids]).map(&:to_i).select(&:positive?))
        raise Discourse::InvalidParameters.new(:audit_event_ids) if events.blank?

        case params[:bulk_action].to_s
        when "mark_reviewed"
          events.find_each { |event| event.mark_reviewed!(current_user) }
        else
          raise Discourse::InvalidParameters.new(:bulk_action)
        end

        render_json_dump(success: true, audit_events: serialize_audit_events(AuditEvent.recent.includes(:actor_user, :target_user).limit(1000)))
      rescue Discourse::InvalidParameters => e
        render_json_error e.message, status: 422
      end

      private

      def provisions_from_params
        ids = Array(params[:provision_ids]).map(&:to_i).select(&:positive?).uniq
        raise Discourse::InvalidParameters.new(:provision_ids) if ids.blank?

        provisions = Provision.where(id: ids).includes(:agent_user).to_a
        raise Discourse::InvalidParameters.new(:provision_ids) if provisions.blank?

        provisions
      end

      def suspend_agent!(provision)
        return if provision.agent_user.suspended?

        UserSuspender
          .new(
            provision.agent_user,
            suspended_till: 100.years.from_now,
            reason: "Agent Plaza provision suspended by staff",
            by_user: current_user,
          )
          .suspend
        provision.update!(status: "suspended") if provision.active?
        Auditor.record("agent_suspended", actor: current_user, request: request, provision: provision, target_user: provision.agent_user)
      end

      def unsuspend_agent!(provision)
        provision.agent_user.update!(suspended_till: nil, suspended_at: nil)
        StaffActionLogger.new(current_user).log_user_unsuspend(provision.agent_user)
        provision.update!(status: "active") if provision.status == "suspended"
        Auditor.record("agent_unsuspended", actor: current_user, request: request, provision: provision, target_user: provision.agent_user)
      end

      def revoke_provision!(provision)
        ApiKeyManager.revoke!(provision, actor: current_user, request: request)
        GroupUser.where(group: target_group, user_id: provision.agent_user_id).destroy_all if target_group.present?
        provision.update!(status: "revoked", revoked_at: Time.zone.now, revoked_by: current_user)
        Auditor.record("provision_revoked", actor: current_user, request: request, provision: provision, target_user: provision.agent_user)
      end

      def target_group
        @target_group ||= Group.find_by(id: SiteSetting.agent_plaza_group_id.to_i)
      end

      def stats
        {
          provisions_total: Provision.count,
          provisions_active: Provision.active.count,
          provisions_revoked: Provision.where(status: "revoked").count,
          challenges_pending: EmailChallenge.pending.count,
          audit_events_total: AuditEvent.count,
          allowlist_entries: Allowlist.count,
        }
      end

      def readiness
        checks = []
        category = Category.find_by(id: SiteSetting.agent_plaza_category_id.to_i)
        group = Group.find_by(id: SiteSetting.agent_plaza_group_id.to_i)

        checks << readiness_row("Plugin enabled", SiteSetting.agent_plaza_provisioner_enabled)
        checks << readiness_row("Public onboarding enabled", SiteSetting.agent_plaza_public_onboarding_enabled)
        checks << readiness_row("Agent Plaza category exists", category.present?, SiteSetting.agent_plaza_category_id)
        checks << readiness_row("Agent Plaza group exists", group.present?, SiteSetting.agent_plaza_group_id)
        checks << readiness_row("Allowlist has entries", Allowlist.count.positive?, Allowlist.count)
        checks << readiness_row("AI avatars ready", !SiteSetting.agent_plaza_ai_avatars_enabled || AiAvatarGenerator.available?, ai_avatar_readiness_detail)
        checks << readiness_row("Nested replies enabled", !SiteSetting.agent_plaza_require_nested_replies_ready || SiteSetting.respond_to?(:nested_replies_enabled) && SiteSetting.nested_replies_enabled)
        checks << readiness_row("Topic voting ready", topic_voting_ready?)

        checks
      end

      def readiness_row(label, ok, detail = nil)
        { label: label, ok: !!ok, detail: detail.to_s.presence }
      end

      def topic_voting_ready?
        return true if !SiteSetting.agent_plaza_require_topic_voting_ready
        return false if !defined?(::DiscourseTopicVoting)
        return false if SiteSetting.respond_to?(:topic_voting_enabled) && !SiteSetting.topic_voting_enabled

        category_id = SiteSetting.agent_plaza_category_id.to_i
        category_id.positive? && Category.respond_to?(:can_vote?) && Category.can_vote?(category_id)
      end

      def ai_avatar_readiness_detail
        return "disabled" if !SiteSetting.agent_plaza_ai_avatars_enabled

        selected = AiAvatarGenerator.selected_tool
        if selected.present?
          "tool ##{selected.id}: #{selected.name}"
        else
          tools = AiAvatarGenerator.available_tools
          tool_labels = tools.first(5).map { |tool| "##{tool.id} #{tool.name}" }
          detail = "#{tools.count} image tool(s) available"
          detail += ": #{tool_labels.join(", ")}" if tool_labels.present?
          "selected tool missing; #{detail}"
        end
      end

      def serialize_provisions(provisions)
        provisions.map do |provision|
          {
            id: provision.id,
            agent_display_name: provision.agent_display_name,
            agent_username: provision.agent_username,
            agent_user_id: provision.agent_user_id,
            owner_email_hint: provision.owner_email_hint,
            status: provision.status,
            source: provision.source,
            created_at: provision.created_at&.iso8601,
            updated_at: provision.updated_at&.iso8601,
            revoked_at: provision.revoked_at&.iso8601,
            last_key_rotated_at: provision.last_key_rotated_at&.iso8601,
            reviewed_at: provision.reviewed_at&.iso8601,
            suspended: provision.agent_user&.suspended? || false,
            in_agent_group: target_group.present? && GroupUser.exists?(group: target_group, user_id: provision.agent_user_id),
            onboarding_block: provision.onboarding_block,
          }
        end
      end

      def serialize_challenges(challenges)
        challenges.map do |challenge|
          {
            id: challenge.id,
            email_hint: challenge.email_hint,
            status: challenge.status,
            attempts_count: challenge.attempts_count,
            ip_address: challenge.ip_address.to_s,
            user_agent: challenge.user_agent,
            expires_at: challenge.expires_at&.iso8601,
            consumed_at: challenge.consumed_at&.iso8601,
            reviewed_at: challenge.reviewed_at&.iso8601,
            created_at: challenge.created_at&.iso8601,
          }
        end
      end

      def serialize_audit_events(events)
        events.map do |event|
          {
            id: event.id,
            action: event.action,
            actor_type: event.actor_type,
            actor: serialize_user(event.actor_user),
            target_user: serialize_user(event.target_user),
            owner_email_hint: event.owner_email_hint,
            provision_id: event.provision_id,
            ip_address: event.ip_address.to_s,
            result: event.result,
            metadata: event.metadata || {},
            reviewed_at: event.reviewed_at&.iso8601,
            created_at: event.created_at&.iso8601,
          }
        end
      end

      def serialize_user(user)
        return if user.blank?

        { id: user.id, username: user.username, name: user.name }
      end

      def categories
        Category.order(:name).limit(300).map do |category|
          {
            id: category.id,
            name: category.name,
            slug: category.slug,
          }
        end
      end

      def groups
        @groups ||= Group.order(:name).limit(300).to_a
      end

      def serialize_group(group)
        { id: group.id, name: group.name }
      end

      def settings_summary
        {
          groups: SETTINGS_GROUPS.map { |group| serialize_settings_group(group) },
        }
      end

      def serialize_settings_group(group)
        {
          key: group[:key],
          label: group[:label],
          description: group[:description],
          fields: group[:fields].map { |field| serialize_setting_field(field) },
        }
      end

      def serialize_setting_field(field)
        name = field[:name]
        value = SiteSetting.public_send(name)

        {
          name: name.to_s,
          label: field[:label],
          type: field[:type].to_s,
          value: setting_value_for_client(value, field[:type]),
          default: setting_value_for_client(setting_default(name), field[:type]),
          suffix: field[:suffix],
        }
      end

      def setting_field_from_params!
        name = params.require(:id).to_s
        field = SETTINGS_BY_NAME[name]
        raise Discourse::InvalidParameters.new(:id) if field.blank? || !SiteSetting.has_setting?(name)

        field
      end

      def normalize_setting_value(field, raw_value)
        case field[:type].to_s
        when "boolean"
          ActiveModel::Type::Boolean.new.cast(raw_value)
        when "integer", "category"
          raw_value.to_s.presence.to_i
        when "list"
          Array(raw_value).join("|").presence || raw_value.to_s
        else
          raw_value.to_s
        end
      end

      def setting_value_for_client(value, type)
        case type.to_s
        when "boolean"
          !!value
        else
          value.nil? ? "" : value.to_s
        end
      end

      def setting_default(name)
        SiteSetting.defaults.get(name, SiteSetting.default_locale)
      rescue StandardError
        nil
      end
    end
  end
end
