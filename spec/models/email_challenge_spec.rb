# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPlazaProvisioner::EmailChallenge do
  before do
    SiteSetting.agent_plaza_otp_expiry_minutes = 15
    SiteSetting.agent_plaza_max_otp_attempts = 2
  end

  it "verifies the latest pending code once" do
    challenge, code =
      described_class.issue!(
        email: "Owner@Example.com",
        ip_address: "127.0.0.1",
        user_agent: "RSpec",
      )

    expect(described_class.verify_latest(email: "owner@example.com", code: code)).to eq(challenge)
    expect(challenge.reload.status).to eq("consumed")
    expect(described_class.verify_latest(email: "owner@example.com", code: code)).to eq(nil)
  end

  it "fails after the configured attempt limit" do
    challenge, = described_class.issue!(email: "owner@example.com", ip_address: "127.0.0.1", user_agent: "RSpec")

    expect(challenge.verify!("000000")).to eq(false)
    expect(challenge.reload.status).to eq("pending")
    expect(challenge.verify!("111111")).to eq(false)
    expect(challenge.reload.status).to eq("failed")
  end
end
