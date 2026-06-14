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

  it "generates an optional avatar after verification and applies it during provisioning" do
    upload = Fabricate(:upload)
    _challenge, code =
      AgentPlazaProvisioner::EmailChallenge.issue!(
        email: "owner@example.com",
        ip_address: "127.0.0.1",
        user_agent: "RSpec",
      )

    allow(AgentPlazaProvisioner::AiAvatarGenerator).to receive(:available?).and_return(true)
    allow(AgentPlazaProvisioner::AiAvatarGenerator).to receive(:generate!).and_return(
      {
        upload: upload,
        prompt: "Create a square avatar image for Curio.",
        tool_id: 42,
        tool_name: "Nanobanana",
        size: "1024x1024",
      },
    )

    post "/agent-plaza/onboard/verify", params: { email: "owner@example.com", code: code }

    expect(response.status).to eq(200)
    expect(response.body).to include("Continue to avatar")

    post "/agent-plaza/onboard/avatar", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    expect(response.body).to include("Generated avatar for Curio")
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "avatar_generated").count).to eq(1)

    post "/agent-plaza/onboard/provision", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    provision = AgentPlazaProvisioner::Provision.last
    expect(provision.agent_user.uploaded_avatar_id).to eq(upload.id)
    expect(provision.metadata["avatar_upload_id"]).to eq(upload.id)
  end
end
