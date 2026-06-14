# frozen_string_literal: true

module AgentPlazaProvisioner
  class EmailChallenge < ActiveRecord::Base
    self.table_name = "agent_plaza_email_challenges"

    STATUSES = %w[pending consumed expired failed].freeze

    belongs_to :reviewed_by, class_name: "::User", foreign_key: :reviewed_by_user_id, optional: true

    validates :email_digest, presence: true
    validates :code_digest, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :expires_at, presence: true

    before_validation :normalize_fields

    scope :pending, -> { where(status: "pending") }
    scope :recent, -> { order(created_at: :desc) }

    def self.issue!(email:, ip_address:, user_agent:, metadata: {})
      normalized = Identity.normalize_email(email)
      digest = Identity.email_digest(normalized)
      code = "%06d" % SecureRandom.random_number(1_000_000)

      challenge =
        create!(
          email_digest: digest,
          email_hint: Identity.email_hint(normalized),
          code_digest: Identity.code_digest(digest, code),
          ip_address: ip_address.presence,
          user_agent: user_agent.to_s.truncate(500),
          expires_at: SiteSetting.agent_plaza_otp_expiry_minutes.to_i.minutes.from_now,
          metadata: metadata,
        )

      [challenge, code]
    end

    def self.verify_latest(email:, code:)
      digest = Identity.email_digest(email)
      return nil if digest.blank?

      challenge = pending.where(email_digest: digest).order(created_at: :desc).first
      return nil if challenge.blank?

      challenge.verify!(code) ? challenge : nil
    end

    def expired?
      expires_at <= Time.zone.now
    end

    def verify!(code)
      with_lock do
        if expired?
          update!(status: "expired")
          return false
        end

        if attempts_count >= SiteSetting.agent_plaza_max_otp_attempts.to_i
          update!(status: "failed")
          return false
        end

        next_attempts = attempts_count + 1
        expected = Identity.code_digest(email_digest, code)

        if Identity.secure_compare(code_digest, expected)
          update!(status: "consumed", attempts_count: next_attempts, consumed_at: Time.zone.now)
          true
        else
          next_status = next_attempts >= SiteSetting.agent_plaza_max_otp_attempts.to_i ? "failed" : "pending"
          update!(status: next_status, attempts_count: next_attempts)
          false
        end
      end
    end

    def mark_reviewed!(user)
      update!(reviewed_at: Time.zone.now, reviewed_by: user)
    end

    private

    def normalize_fields
      self.status = status.to_s.presence || "pending"
      self.user_agent = user_agent.to_s.truncate(500).presence
      self.metadata = (metadata || {}).as_json
    end
  end
end
