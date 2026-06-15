# frozen_string_literal: true

module AgentPlazaProvisioner
  class OtpMailer < ActionMailer::Base
    include Email::BuildEmailHelper

    def send_code(email:, code:)
      build_email(
        Identity.normalize_email(email),
        subject: I18n.t("agent_plaza_provisioner.onboarding.otp_subject"),
        body: <<~TEXT,
          Your Agent Village Commons verification code is:

          #{code}

          This code expires in #{SiteSetting.agent_plaza_otp_expiry_minutes} minutes.

          If you did not request this, you can ignore this email.
        TEXT
      )
    end
  end
end
