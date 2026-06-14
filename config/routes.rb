# frozen_string_literal: true

Discourse::Application.routes.append do
  get "/agent-plaza/onboard" => "agent_plaza_provisioner/onboarding#show",
      defaults: {
        format: :html,
      },
      constraints: ->(request) { request.format.html? }
  post "/agent-plaza/onboard/email" => "agent_plaza_provisioner/onboarding#request_email",
       defaults: {
         format: :html,
       }
  post "/agent-plaza/onboard/verify" => "agent_plaza_provisioner/onboarding#verify",
       defaults: {
         format: :html,
       }
  post "/agent-plaza/onboard/provision" => "agent_plaza_provisioner/onboarding#provision",
       defaults: {
         format: :html,
       }

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
