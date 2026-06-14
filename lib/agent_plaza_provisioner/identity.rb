# frozen_string_literal: true

require "openssl"
require "set"
require "uri"

module ::AgentPlazaProvisioner
  module Identity
    MIN_AGENT_NAME_LENGTH = 2
    MAX_AGENT_NAME_LENGTH = 60

    module_function

    def normalize_email(email)
      email.to_s.strip.downcase.presence
    end

    def valid_email?(email)
      normalized = normalize_email(email)
      normalized.present? && normalized.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def email_digest(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      hmac(normalized)
    end

    def email_hint(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      local, domain = normalized.split("@", 2)
      return normalized if domain.blank?

      visible = local[0].to_s
      "#{visible}***@#{domain}"
    end

    def code_digest(email_digest, code)
      hmac("#{email_digest}:#{code.to_s.strip}")
    end

    def secure_compare(a, b)
      a = a.to_s
      b = b.to_s
      return false if a.bytesize != b.bytesize

      Rack::Utils.secure_compare(a, b)
    end

    def normalize_agent_name(name)
      name.to_s.gsub(/\s+/, " ").strip.presence
    end

    def normalized_agent_name_key(name)
      normalize_agent_name(name).to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
    end

    def reserved_agent_name?(name)
      key = normalized_agent_name_key(name)
      return true if key.blank?

      reserved_agent_name_keys.include?(key)
    end

    def valid_agent_name?(name)
      normalized = normalize_agent_name(name)
      max_length = agent_name_max_length
      normalized.present? &&
        max_length >= MIN_AGENT_NAME_LENGTH &&
        normalized.length.between?(MIN_AGENT_NAME_LENGTH, max_length)
    end

    def username_for_agent_name(name)
      base = username_base_for_agent_name(name)
      base = "#{username_prefix}#{SecureRandom.hex(3)}" if base.blank?
      UserNameSuggester.suggest(base)
    end

    def agent_name_max_length
      max_username_length = SiteSetting.max_username_length.to_i
      max_username_length = User.username_length.end if max_username_length <= 0
      [max_username_length - username_prefix.length, MAX_AGENT_NAME_LENGTH].min
    end

    def username_prefix
      SiteSetting.agent_plaza_username_prefix.to_s.presence || "agent_"
    end

    def username_base_for_agent_name(name)
      UserNameSuggester.sanitize_username("#{username_prefix}#{normalize_agent_name(name)}")
    end

    def synthetic_email_for_username(username)
      domain = SiteSetting.agent_plaza_synthetic_email_domain.to_s.strip.presence || "agent-plaza.invalid"
      "#{username}@#{domain}"
    end

    def hmac(value)
      OpenSSL::HMAC.hexdigest("SHA256", GlobalSetting.safe_secret_key_base.to_s, value.to_s)
    end

    def reserved_agent_name_keys
      SiteSetting
        .agent_plaza_reserved_agent_names
        .to_s
        .split(/[|,\n]/)
        .map { |name| normalized_agent_name_key(name) }
        .select(&:present?)
        .to_set
    end
  end
end
