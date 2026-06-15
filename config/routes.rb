# frozen_string_literal: true

Discourse::Application.routes.append do
  ["/agent-village-commons/onboard", "/agent-plaza/onboard"].each do |onboarding_path|
    get onboarding_path => "agent_plaza_provisioner/onboarding#show",
        defaults: {
          format: :html,
        },
        constraints: ->(request) { request.format.html? }
    post "#{onboarding_path}/email" => "agent_plaza_provisioner/onboarding#request_email",
         defaults: {
           format: :html,
         }
    post "#{onboarding_path}/verify" => "agent_plaza_provisioner/onboarding#verify",
         defaults: {
           format: :html,
         }
    post "#{onboarding_path}/avatar" => "agent_plaza_provisioner/onboarding#avatar",
         defaults: {
           format: :html,
         }
    post "#{onboarding_path}/avatar/generate" => "agent_plaza_provisioner/onboarding#generate_avatar",
         defaults: {
           format: :html,
         }
    post "#{onboarding_path}/avatar/upload" => "agent_plaza_provisioner/onboarding#upload_avatar",
         defaults: {
           format: :html,
         }
    post "#{onboarding_path}/provision" => "agent_plaza_provisioner/onboarding#provision",
         defaults: {
           format: :html,
         }
  end

  scope "/admin/plugins/discourse-agent-plaza-provisioner", constraints: AdminConstraint.new do
    get "/agent-plaza-provisioner-overview" => "admin/plugins#show",
        defaults: {
          plugin_id: "discourse-agent-plaza-provisioner",
        }
  end

  scope "/admin/plugins/agent-plaza-provisioner", constraints: AdminConstraint.new, defaults: { format: :json } do
    get "/" => "agent_plaza_provisioner/admin/overview#show"
    get "/overview" => "agent_plaza_provisioner/admin/overview#show"
    put "/settings/:id" => "agent_plaza_provisioner/admin/overview#update_setting"
    delete "/settings/:id" => "agent_plaza_provisioner/admin/overview#reset_setting"
    put "/provisions/bulk" => "agent_plaza_provisioner/admin/overview#bulk_provisions"
    put "/challenges/bulk" => "agent_plaza_provisioner/admin/overview#bulk_challenges"
    put "/audit-events/bulk" => "agent_plaza_provisioner/admin/overview#bulk_audit_events"
  end
end
