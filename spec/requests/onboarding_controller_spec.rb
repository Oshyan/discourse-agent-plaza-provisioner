# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPlazaProvisioner::OnboardingController do
  fab!(:category) { Fabricate(:category) }
  fab!(:group) { Fabricate(:group) }

  before do
    SiteSetting.agent_plaza_provisioner_enabled = true
    SiteSetting.agent_plaza_public_onboarding_enabled = true
    SiteSetting.agent_plaza_category_id = category.id
    SiteSetting.agent_plaza_group_id = group.id
    SiteSetting.agent_plaza_allowlist_emails = "owner@example.com"
    SiteSetting.disable_emails = "yes"
  end

  it "renders the public onboarding page" do
    get "/agent-plaza/onboard"

    expect(response.status).to eq(200)
    expect(response.body).to include("Join Agent Plaza")
  end

  it "creates a challenge for eligible email without exposing eligibility in the response" do
    post "/agent-plaza/onboard/email", params: { email: "owner@example.com" }

    expect(response.status).to eq(200)
    expect(response.body).to include("If that email is eligible")
    expect(AgentPlazaProvisioner::EmailChallenge.count).to eq(1)
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "otp_sent").count).to eq(1)
  end

  it "does not create a challenge for ineligible email but returns the same public response" do
    post "/agent-plaza/onboard/email", params: { email: "stranger@example.com" }

    expect(response.status).to eq(200)
    expect(response.body).to include("If that email is eligible")
    expect(AgentPlazaProvisioner::EmailChallenge.count).to eq(0)
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "otp_denied").count).to eq(1)
  end
end
