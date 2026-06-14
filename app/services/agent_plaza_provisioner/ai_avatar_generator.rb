# frozen_string_literal: true

module AgentPlazaProvisioner
  class AiAvatarGenerator
    DEFAULT_SIZE = "1024x1024"
    FEATURE_NAME = "agent_plaza_avatar_generation"

    class << self
      def available?
        SiteSetting.agent_plaza_ai_avatars_enabled &&
          discourse_ai_available? &&
          selected_tool.present?
      end

      def available_tools
        return [] if !discourse_ai_available?

        ::AiTool
          .where(enabled: true, is_image_generation_tool: true)
          .order(:name)
          .to_a
      rescue StandardError
        []
      end

      def selected_tool
        tool_id = SiteSetting.agent_plaza_ai_avatar_generation_tool_id.to_i
        return if tool_id <= 0

        available_tools.find { |tool| tool.id == tool_id }
      end

      def prompt_for(agent_name)
        normalized_name = Identity.normalize_agent_name(agent_name)
        raise ArgumentError, "Agent name cannot be blank." if normalized_name.blank?

        template = SiteSetting.agent_plaza_ai_avatar_prompt_template.to_s.presence || default_prompt_template
        template.gsub("{{agent_name}}", normalized_name)
      end

      def generate!(agent_name:, user:, guardian:, size: nil)
        raise ArgumentError, I18n.t("agent_plaza_provisioner.errors.avatar_generation_unavailable") if !available?

        prompt = prompt_for(agent_name)
        tool = selected_tool
        raise ArgumentError, I18n.t("agent_plaza_provisioner.errors.avatar_generation_unavailable") if tool.blank?

        tool_class = ::DiscourseAi::Agents::Tools::Custom.class_instance(tool.id)
        actor = user.presence || Discourse.system_user
        context =
          ::DiscourseAi::Agents::BotContext.new(
            user: actor,
            guardian: guardian || Guardian.new(actor),
            feature_name: FEATURE_NAME,
            messages: [
              {
                type: :user,
                content: prompt,
              },
            ],
          )

        tool_instance =
          tool_class.new(
            {
              prompt: prompt,
              size: normalized_size(size),
            },
            bot_user: actor,
            llm: nil,
            context: context,
          )
        result = tool_instance.invoke { |_raw, _custom| }
        error = result[:error] || result["error"] if result.respond_to?(:[])
        raise ArgumentError, error if error.present?

        upload = upload_from_custom_raw(tool_instance.custom_raw) if tool_instance.respond_to?(:custom_raw)
        upload ||= upload_from_result(result)
        raise ArgumentError, "Discourse AI did not return an avatar image upload." if upload.blank?

        { upload: upload, prompt: prompt, tool_id: tool.id, tool_name: tool.name, size: normalized_size(size) }
      end

      private

      def default_prompt_template
        SiteSetting.defaults.get(:agent_plaza_ai_avatar_prompt_template, SiteSetting.default_locale).to_s
      rescue StandardError
        %(Create a square avatar image for an AI bot/agent named "{{agent_name}}". Do not include text, logos, watermarks, or UI. Output a 1:1 square image.)
      end

      def normalized_size(size)
        size.to_s.strip.presence || SiteSetting.agent_plaza_ai_avatar_size.to_s.strip.presence || DEFAULT_SIZE
      end

      def discourse_ai_available?
        defined?(::AiTool) &&
          defined?(::DiscourseAi::Agents::Tools::Custom) &&
          defined?(::DiscourseAi::Agents::BotContext) &&
          ::AiTool.respond_to?(:table_exists?) &&
          ::AiTool.table_exists? &&
          ::AiTool.column_names.include?("is_image_generation_tool")
      rescue StandardError
        false
      end

      def upload_from_custom_raw(custom_raw)
        short_url = custom_raw.to_s[%r{upload://[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)?}]
        upload_from_short_url(short_url)
      end

      def upload_from_result(result)
        return if !result.respond_to?(:[])

        short_url = result[:url] || result["url"]
        short_url ||= result.dig(:image, :url) if result.respond_to?(:dig)
        short_url ||= result.dig("image", "url") if result.respond_to?(:dig)
        upload_from_short_url(short_url)
      end

      def upload_from_short_url(short_url)
        return if short_url.blank?

        sha1 = Upload.sha1_from_short_url(short_url)
        Upload.find_by(sha1: sha1) if sha1.present?
      end
    end
  end
end
