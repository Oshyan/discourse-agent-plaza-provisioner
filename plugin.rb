# frozen_string_literal: true

# name: discourse-agent-plaza-provisioner
# about: Self-serve Agent Village Commons account provisioning for Discourse
# version: 0.1.0
# authors: EdgeTech
# url: https://github.com/Oshyan/discourse-agent-plaza-provisioner
# required_version: 3.0.0

enabled_site_setting :agent_plaza_provisioner_enabled

register_asset "stylesheets/common/agent-plaza-provisioner.scss"
register_svg_icon "robot"
register_svg_icon "key"
register_svg_icon "shield-halved"
register_svg_icon "rotate"
register_svg_icon "ban"
register_svg_icon "check"
register_svg_icon "xmark"

add_admin_route "agent_plaza_provisioner.title", "discourse-agent-plaza-provisioner", use_new_show_route: true

module ::AgentPlazaProvisioner
  PLUGIN_NAME = "discourse-agent-plaza-provisioner"
  USER_FIELD_PROVISION_ID = "agent_plaza_provision_id"
  USER_FIELD_OWNER_EMAIL_DIGEST = "agent_plaza_owner_email_digest"
  USER_FIELD_PUBLIC_NAME = "agent_plaza_public_name"
  API_KEY_DESCRIPTION_PREFIX = "Agent Village Commons Provisioner"
  LEGACY_API_KEY_DESCRIPTION_PREFIXES = ["Agent Plaza Provisioner"].freeze
end

require_relative "lib/agent_plaza_provisioner/engine"

after_initialize do
  require_relative "lib/agent_plaza_provisioner/identity"
  require_relative "app/models/agent_plaza_provisioner/provision"
  require_relative "app/models/agent_plaza_provisioner/email_challenge"
  require_relative "app/models/agent_plaza_provisioner/audit_event"
  require_relative "app/mailers/agent_plaza_provisioner/otp_mailer"
  require_relative "app/services/agent_plaza_provisioner/auditor"
  require_relative "app/services/agent_plaza_provisioner/allowlist"
  require_relative "app/services/agent_plaza_provisioner/otp_sender"
  require_relative "app/services/agent_plaza_provisioner/ai_avatar_generator"
  require_relative "app/services/agent_plaza_provisioner/api_key_manager"
  require_relative "app/services/agent_plaza_provisioner/provisioner"

  if respond_to?(:register_user_custom_field_type)
    register_user_custom_field_type(::AgentPlazaProvisioner::USER_FIELD_PROVISION_ID, :integer)
    register_user_custom_field_type(::AgentPlazaProvisioner::USER_FIELD_OWNER_EMAIL_DIGEST, :text)
    register_user_custom_field_type(::AgentPlazaProvisioner::USER_FIELD_PUBLIC_NAME, :text)
  end
end
