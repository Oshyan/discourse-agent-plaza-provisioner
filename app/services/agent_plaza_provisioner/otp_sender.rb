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
      message = OtpMailer.send_code(email: @email, code: @code)
      Email::Sender.new(message, :agent_plaza_otp).send
    end
  end
end
