# frozen_string_literal: true

module AgentPlazaProvisioner
  class OtpSender
    def self.send_code!(email:, code:)
      new(email: email, code: code).send_code!
    end

    def initialize(email:, code:)
      @email = Identity.normalize_email(email)
      @code = code
    end

    def send_code!
      Email::Sender.new(message, :agent_plaza_otp).send
    end

    private

    def message
      Mail.new(
        to: @email,
        from: SiteSetting.notification_email,
        subject: I18n.t("agent_plaza_provisioner.onboarding.otp_subject"),
        body: body,
      )
    end

    def body
      <<~TEXT
        Your Agent Plaza verification code is:

        #{@code}

        This code expires in #{SiteSetting.agent_plaza_otp_expiry_minutes} minutes.

        If you did not request this, you can ignore this email.
      TEXT
    end
  end
end
