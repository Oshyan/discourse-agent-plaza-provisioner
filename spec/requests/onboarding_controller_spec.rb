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
    SiteSetting.agent_plaza_username_prefix = "agent_"
    SiteSetting.max_username_length = 20
    SiteSetting.disable_emails = "yes"
  end

  it "renders the public onboarding page" do
    get "/agent-village-commons/onboard"

    expect(response.status).to eq(200)
    expect(response.body).to include("Join Agent Village Commons")
  end

  it "keeps the legacy Agent Plaza onboarding path working" do
    get "/agent-plaza/onboard"

    expect(response.status).to eq(200)
    expect(response.body).to include("Join Agent Village Commons")
  end

  it "creates a challenge for eligible email without exposing eligibility in the response" do
    post "/agent-village-commons/onboard/email", params: { email: "owner@example.com" }

    expect(response.status).to eq(200)
    expect(response.body).to include("If that email is eligible")
    expect(AgentPlazaProvisioner::EmailChallenge.count).to eq(1)
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "otp_sent").count).to eq(1)
  end

  it "does not create a challenge for ineligible email but returns the same public response" do
    post "/agent-village-commons/onboard/email", params: { email: "stranger@example.com" }

    expect(response.status).to eq(200)
    expect(response.body).to include("If that email is eligible")
    expect(AgentPlazaProvisioner::EmailChallenge.count).to eq(0)
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "otp_denied").count).to eq(1)
  end

  it "shows avatar choices after naming without automatically generating an avatar" do
    _challenge, code =
      AgentPlazaProvisioner::EmailChallenge.issue!(
        email: "owner@example.com",
        ip_address: "127.0.0.1",
        user_agent: "RSpec",
      )

    allow(AgentPlazaProvisioner::AiAvatarGenerator).to receive(:available?).and_return(true)
    expect(AgentPlazaProvisioner::AiAvatarGenerator).not_to receive(:generate!)

    post "/agent-village-commons/onboard/verify", params: { email: "owner@example.com", code: code }

    expect(response.status).to eq(200)
    expect(response.body).to include("Continue")
    expect(response.body).to include('maxlength="14"')
    expect(response.body).to include("Use 14 characters or fewer")

    post "/agent-village-commons/onboard/avatar", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    expect(response.body).to include("Choose an Avatar")
    expect(response.body).to include("Generate Avatar")
    expect(response.body).to include("Upload Avatar")
    expect(response.body).to include("Skip Avatar and Create Account")
    expect(response.body).not_to include("Create account without avatar")
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "avatar_generated").count).to eq(0)
  end

  it "rejects names that would produce truncated API usernames" do
    _challenge, code =
      AgentPlazaProvisioner::EmailChallenge.issue!(
        email: "owner@example.com",
        ip_address: "127.0.0.1",
        user_agent: "RSpec",
      )

    post "/agent-village-commons/onboard/verify", params: { email: "owner@example.com", code: code }
    post "/agent-village-commons/onboard/avatar", params: { agent_name: "Curioer and Curioer" }

    expect(response.status).to eq(200)
    expect(response.body).to include("Use a name between 2 and 14 characters")
  end

  it "generates an optional avatar only when requested and applies it during provisioning" do
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

    post "/agent-village-commons/onboard/verify", params: { email: "owner@example.com", code: code }

    expect(response.status).to eq(200)
    expect(response.body).to include("Continue")

    post "/agent-village-commons/onboard/avatar/generate", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    expect(response.body).to include("Selected avatar for Curio")
    expect(response.body).to include("Generate Another")
    expect(response.body).to include("Use Avatar")
    expect(response.body).to include("Skip Avatar and Create Account")
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "avatar_generated").count).to eq(1)

    post "/agent-village-commons/onboard/provision", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    provision = AgentPlazaProvisioner::Provision.last
    expect(provision.agent_user.uploaded_avatar_id).to eq(upload.id)
    expect(provision.metadata["avatar_upload_id"]).to eq(upload.id)
  end

  it "uploads an optional avatar and applies it during provisioning" do
    upload = Fabricate(:upload)
    creator = instance_double(UploadCreator, create_for: upload)
    uploaded_file = Rack::Test::UploadedFile.new(file_from_fixtures("logo.png"))
    _challenge, code =
      AgentPlazaProvisioner::EmailChallenge.issue!(
        email: "owner@example.com",
        ip_address: "127.0.0.1",
        user_agent: "RSpec",
      )

    allow(UploadCreator).to receive(:new).and_return(creator)

    post "/agent-village-commons/onboard/verify", params: { email: "owner@example.com", code: code }
    post "/agent-village-commons/onboard/avatar/upload", params: { agent_name: "Curio", avatar_file: uploaded_file }

    expect(response.status).to eq(200)
    expect(response.body).to include("Avatar uploaded")
    expect(UploadCreator).to have_received(:new)
    expect(AgentPlazaProvisioner::AuditEvent.where(action: "avatar_uploaded").count).to eq(1)

    post "/agent-village-commons/onboard/provision", params: { agent_name: "Curio" }

    expect(response.status).to eq(200)
    provision = AgentPlazaProvisioner::Provision.last
    expect(provision.agent_user.uploaded_avatar_id).to eq(upload.id)
    expect(provision.metadata["avatar_upload_id"]).to eq(upload.id)
    expect(provision.metadata["avatar_generation"]["source"]).to eq("upload")
  end
end
