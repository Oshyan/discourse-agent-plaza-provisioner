# frozen_string_literal: true

module AgentPlazaProvisioner
  class Allowlist
    def self.eligible?(email)
      new.eligible?(email)
    end

    def self.count
      new.entries.count
    end

    def eligible?(email)
      normalized = Identity.normalize_email(email)
      return false if normalized.blank?

      entries.any? do |entry|
        if entry.start_with?("*@")
          normalized.end_with?("@#{entry.delete_prefix("*@")}")
        else
          normalized == entry
        end
      end
    end

    def entries
      SiteSetting
        .agent_plaza_allowlist_emails
        .to_s
        .split(/[|,\n\s]+/)
        .map { |email| Identity.normalize_email(email) }
        .select { |email| email.present? && (email.start_with?("*@") || Identity.valid_email?(email)) }
        .uniq
    end
  end
end
