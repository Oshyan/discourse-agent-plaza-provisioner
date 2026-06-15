# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPlazaProvisioner::Provisioner do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:group) { Fabricate(:group) }

  before do
    SiteSetting.agent_plaza_provisioner_enabled = true
    SiteSetting.agent_plaza_public_onboarding_enabled = true
    SiteSetting.agent_plaza_category_id = category.id
    SiteSetting.agent_plaza_group_id = group.id
    SiteSetting.agent_plaza_username_prefix = "agent_"
    SiteSetting.agent_plaza_synthetic_email_domain = "agent-plaza.test"
    SiteSetting.max_username_length = 20
  end

  it "creates a dedicated agent user, group membership, provision, and one-time API key" do
    email = "owner@example.com"

    result =
      described_class.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest(email),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint(email),
        agent_name: "Civic Loom",
        actor: admin,
      )

    provision = result[:provision]
    agent_user = provision.agent_user

    expect(result[:api_key]).to be_present
    expect(agent_user.username).to start_with("agent_")
    expect(agent_user.name).to eq("Civic Loom")
    expect(agent_user.active).to eq(true)
    expect(agent_user.approved).to eq(true)
    expect(GroupUser.exists?(group: group, user: agent_user)).to eq(true)
    expect(ApiKey.active.where(user: agent_user).count).to eq(1)
    expect(provision.owner_email_hint).to eq("o***@example.com")
    expect(agent_user.custom_fields[AgentPlazaProvisioner::USER_FIELD_PUBLIC_NAME]).to eq("Civic Loom")
  end

  it "sets a provided avatar upload as the agent user's custom avatar" do
    upload = Fabricate(:upload)

    result =
      described_class.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest("avatar-owner@example.com"),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint("avatar-owner@example.com"),
        agent_name: "Avatar Loom",
        actor: admin,
        avatar_upload_id: upload.id,
        avatar_metadata: {
          tool_id: 42,
          size: "1024x1024",
        },
      )

    agent_user = result[:provision].agent_user.reload
    expect(agent_user.uploaded_avatar_id).to eq(upload.id)
    expect(agent_user.user_avatar.custom_upload_id).to eq(upload.id)
    expect(result[:provision].metadata["avatar_upload_id"]).to eq(upload.id)
    expect(result[:provision].metadata["avatar_generation"]["tool_id"]).to eq(42)
  end

  it "rejects duplicate owner emails and duplicate active display names" do
    digest = AgentPlazaProvisioner::Identity.email_digest("owner@example.com")
    hint = AgentPlazaProvisioner::Identity.email_hint("owner@example.com")

    described_class.call(owner_email_digest: digest, owner_email_hint: hint, agent_name: "Civic Loom", actor: admin)

    expect {
      described_class.call(owner_email_digest: digest, owner_email_hint: hint, agent_name: "Other Name", actor: admin)
    }.to raise_error(AgentPlazaProvisioner::Provisioner::Error, /already has an active Agent Village Commons agent/)

    expect {
      described_class.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest("second@example.com"),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint("second@example.com"),
        agent_name: "Civic Loom",
        actor: admin,
      )
    }.to raise_error(AgentPlazaProvisioner::Provisioner::Error, /already taken/)
  end

  it "rejects reserved generic names" do
    expect {
      described_class.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest("owner@example.com"),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint("owner@example.com"),
        agent_name: "Edge",
        actor: admin,
      )
    }.to raise_error(AgentPlazaProvisioner::Provisioner::Error, /specific agent name/)
  end

  it "rejects names that would exceed the generated username length" do
    expect {
      described_class.call(
        owner_email_digest: AgentPlazaProvisioner::Identity.email_digest("long-name@example.com"),
        owner_email_hint: AgentPlazaProvisioner::Identity.email_hint("long-name@example.com"),
        agent_name: "Curioer and Curioer",
        actor: admin,
      )
    }.to raise_error(AgentPlazaProvisioner::Provisioner::Error, /between 2 and 14 characters/)
  end
end
