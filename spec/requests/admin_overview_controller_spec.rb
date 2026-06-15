# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPlazaProvisioner::Admin::OverviewController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:group) { Fabricate(:group) }

  before do
    SiteSetting.agent_plaza_provisioner_enabled = true
    SiteSetting.agent_plaza_public_onboarding_enabled = true
    SiteSetting.agent_plaza_category_id = category.id
    SiteSetting.agent_plaza_group_id = group.id
    SiteSetting.agent_plaza_allowlist_emails = "owner@example.com"
    sign_in(admin)
  end

  it "exposes overview data, readiness, settings, and tables" do
    get "/admin/plugins/agent-plaza-provisioner/overview.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["stats"]).to be_present
    expect(response.parsed_body["readiness"].map { |row| row["label"] }).to include("Agent Village Commons category exists")
    expect(response.parsed_body.dig("settings", "groups").map { |group| group["key"] }).to include(
      "onboarding",
      "targets",
      "identity",
      "avatars",
      "readiness",
    )
  end

  it "updates and resets allowed settings" do
    put "/admin/plugins/agent-plaza-provisioner/settings/agent_plaza_username_prefix.json",
        params: {
          value: "plaza_",
        }

    expect(response.status).to eq(200)
    expect(SiteSetting.agent_plaza_username_prefix).to eq("plaza_")

    delete "/admin/plugins/agent-plaza-provisioner/settings/agent_plaza_username_prefix.json"

    expect(response.status).to eq(200)
    expect(SiteSetting.agent_plaza_username_prefix).to eq("agent_")
  end

  it "rotates keys through the provisions bulk endpoint" do
    result =
      AgentPlazaProvisioner::Provisioner.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest("owner@example.com"),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint("owner@example.com"),
        agent_name: "Civic Loom",
        actor: admin,
      )

    provision = result[:provision]
    old_key_hash = ApiKey.active.find_by(user: provision.agent_user).key_hash

    put "/admin/plugins/agent-plaza-provisioner/provisions/bulk.json",
        params: {
          provision_ids: [provision.id],
          bulk_action: "rotate_keys",
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body["rotated_keys"].first["api_key"]).to be_present
    expect(ApiKey.active.find_by(user: provision.agent_user).key_hash).not_to eq(old_key_hash)
  end
end
