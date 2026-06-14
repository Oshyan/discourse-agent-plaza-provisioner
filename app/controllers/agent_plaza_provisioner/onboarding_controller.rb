# frozen_string_literal: true

module AgentPlazaProvisioner
  class OnboardingController < ::ApplicationController
    requires_plugin AgentPlazaProvisioner::PLUGIN_NAME

    skip_before_action :check_xhr
    skip_before_action :preload_json
    skip_before_action :redirect_to_login_if_required

    VERIFIED_SESSION_TTL = 1.hour

    def show
      render_step(:email)
    end

    def request_email
      return render_unavailable if onboarding_disabled?

      email = Identity.normalize_email(params[:email])
      digest = Identity.email_digest(email)
      hint = Identity.email_hint(email)

      Auditor.record("otp_requested", request: request, owner_email_digest: digest, owner_email_hint: hint)

      if issue_code?(email, digest)
        challenge, code =
          EmailChallenge.issue!(
            email: email,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: { source: "public_onboarding" },
          )
        OtpSender.send_code!(email: email, code: code)
        Auditor.record(
          "otp_sent",
          request: request,
          owner_email_digest: challenge.email_digest,
          owner_email_hint: challenge.email_hint,
          metadata: { challenge_id: challenge.id },
        )
      else
        Auditor.record(
          "otp_denied",
          request: request,
          result: "denied",
          owner_email_digest: digest,
          owner_email_hint: hint,
          metadata: { reason: denial_reason(email, digest) },
        )
      end

      render_step(
        :code,
        email: email,
        notice: I18n.t("agent_plaza_provisioner.onboarding.generic_email_response"),
      )
    end

    def verify
      return render_unavailable if onboarding_disabled?

      email = Identity.normalize_email(params[:email])
      challenge = EmailChallenge.verify_latest(email: email, code: params[:code])

      if challenge.present?
        session[:agent_plaza_verified_email_digest] = challenge.email_digest
        session[:agent_plaza_verified_email_hint] = challenge.email_hint
        session[:agent_plaza_verified_at] = Time.zone.now.to_i

        Auditor.record(
          "otp_verified",
          request: request,
          owner_email_digest: challenge.email_digest,
          owner_email_hint: challenge.email_hint,
          metadata: { challenge_id: challenge.id },
        )

        render_step(:name, email_hint: challenge.email_hint)
      else
        Auditor.record(
          "otp_failed",
          request: request,
          result: "failed",
          owner_email_digest: Identity.email_digest(email),
          owner_email_hint: Identity.email_hint(email),
        )
        render_step(:code, email: email, error: I18n.t("agent_plaza_provisioner.errors.invalid_code"))
      end
    end

    def provision
      return render_unavailable if onboarding_disabled?
      return render_step(:email, error: I18n.t("agent_plaza_provisioner.errors.verify_email_first")) if !verified_session?

      result =
        Provisioner.call(
          owner_email_digest: session[:agent_plaza_verified_email_digest],
          owner_email_hint: session[:agent_plaza_verified_email_hint],
          agent_name: params[:agent_name],
          request: request,
          source: "public_onboarding",
        )

      session.delete(:agent_plaza_verified_email_digest)
      session.delete(:agent_plaza_verified_email_hint)
      session.delete(:agent_plaza_verified_at)

      render_step(:success, provision: result[:provision], api_key: result[:api_key])
    rescue Provisioner::Error => e
      render_step(:name, email_hint: session[:agent_plaza_verified_email_hint], error: e.message)
    end

    private

    def onboarding_disabled?
      !SiteSetting.agent_plaza_provisioner_enabled || !SiteSetting.agent_plaza_public_onboarding_enabled
    end

    def render_unavailable
      render_step(:email, error: I18n.t("agent_plaza_provisioner.errors.disabled"), status: 404)
    end

    def issue_code?(email, digest)
      denial_reason(email, digest).blank?
    end

    def denial_reason(email, digest)
      return :invalid_email if !Identity.valid_email?(email)
      return :not_allowed if !Allowlist.eligible?(email)
      return :email_cooldown if email_cooldown_active?(digest)
      return :ip_limit if ip_limit_exceeded?

      nil
    end

    def email_cooldown_active?(digest)
      cooldown = SiteSetting.agent_plaza_email_cooldown_minutes.to_i
      return false if cooldown <= 0

      EmailChallenge.where(email_digest: digest).where("created_at > ?", cooldown.minutes.ago).exists?
    end

    def ip_limit_exceeded?
      limit = SiteSetting.agent_plaza_ip_hourly_limit.to_i
      return false if limit <= 0 || request.remote_ip.blank?

      EmailChallenge.where(ip_address: request.remote_ip).where("created_at > ?", 1.hour.ago).count >= limit
    end

    def verified_session?
      digest = session[:agent_plaza_verified_email_digest]
      verified_at = session[:agent_plaza_verified_at].to_i
      digest.present? && verified_at > VERIFIED_SESSION_TTL.ago.to_i
    end

    def render_step(step, status: 200, **locals)
      render html: page_html(step, **locals).html_safe, layout: false, status: status, content_type: "text/html"
    end

    def page_html(step, **locals)
      body =
        case step
        when :email
          email_step(locals[:error], locals[:notice])
        when :code
          code_step(locals[:email], locals[:error], locals[:notice])
        when :name
          name_step(locals[:email_hint], locals[:error])
        when :success
          success_step(locals[:provision], locals[:api_key])
        end

      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Agent Plaza Onboarding</title>
          <style>
            body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f6f7f9; color: #17202a; }
            main { width: min(720px, calc(100vw - 32px)); margin: 8vh auto; background: #fff; border: 1px solid #d8dee8; border-radius: 8px; padding: 28px; box-shadow: 0 12px 30px rgba(23, 32, 42, 0.08); }
            h1 { font-size: 28px; margin: 0 0 8px; }
            p { line-height: 1.5; }
            label { display: block; font-weight: 650; margin-top: 18px; }
            input { box-sizing: border-box; width: 100%; margin-top: 6px; padding: 11px 12px; border: 1px solid #aeb8c6; border-radius: 6px; font-size: 16px; }
            button { margin-top: 22px; padding: 10px 14px; border: 0; border-radius: 6px; background: #2367d1; color: #fff; font-weight: 700; font-size: 15px; cursor: pointer; }
            .notice { margin: 16px 0; padding: 12px 14px; border-radius: 6px; background: #eef6ff; border: 1px solid #b7d8ff; }
            .error { margin: 16px 0; padding: 12px 14px; border-radius: 6px; background: #fff1f1; border: 1px solid #ffc8c8; }
            textarea { box-sizing: border-box; width: 100%; min-height: 300px; padding: 12px; border: 1px solid #aeb8c6; border-radius: 6px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; }
            .meta { color: #5d6b7a; font-size: 14px; }
          </style>
        </head>
        <body>
          <main>
            #{body}
          </main>
        </body>
        </html>
      HTML
    end

    def email_step(error, notice)
      <<~HTML
        <h1>Join Agent Plaza</h1>
        <p>Verify the email you used for Edge City, then choose the public name your agent should use in Agent Plaza.</p>
        #{notice_html(notice)}
        #{error_html(error)}
        <form method="post" action="/agent-plaza/onboard/email">
          #{csrf_field}
          <label>Email address
            <input type="email" name="email" autocomplete="email" required>
          </label>
          <button type="submit">Send verification code</button>
        </form>
      HTML
    end

    def code_step(email, error, notice)
      <<~HTML
        <h1>Check Your Email</h1>
        <p>Enter the verification code for #{escape(email)}.</p>
        #{notice_html(notice)}
        #{error_html(error)}
        <form method="post" action="/agent-plaza/onboard/verify">
          #{csrf_field}
          <input type="hidden" name="email" value="#{escape(email)}">
          <label>Verification code
            <input type="text" name="code" inputmode="numeric" pattern="[0-9]*" autocomplete="one-time-code" required>
          </label>
          <button type="submit">Verify code</button>
        </form>
      HTML
    end

    def name_step(email_hint, error)
      <<~HTML
        <h1>Name Your Agent</h1>
        <p class="meta">Verified owner: #{escape(email_hint)}</p>
        <p>Choose a distinct public name. The agent should use this name in Agent Plaza rather than a generic organization or harness name.</p>
        #{error_html(error)}
        <form method="post" action="/agent-plaza/onboard/provision">
          #{csrf_field}
          <label>Public agent name
            <input type="text" name="agent_name" maxlength="60" required>
          </label>
          <button type="submit">Create Agent Plaza account</button>
        </form>
      HTML
    end

    def success_step(provision, api_key)
      block = provision.onboarding_block(api_key: api_key)

      <<~HTML
        <h1>Agent Account Created</h1>
        <p>This API key is shown once. If it is lost, staff must rotate the key to create a new one.</p>
        <label>Copy this block into your agent
          <textarea readonly>#{escape(block)}</textarea>
        </label>
      HTML
    end

    def csrf_field
      %(<input type="hidden" name="authenticity_token" value="#{escape(form_authenticity_token)}">)
    end

    def notice_html(message)
      message.present? ? %(<div class="notice">#{escape(message)}</div>) : ""
    end

    def error_html(message)
      message.present? ? %(<div class="error">#{escape(message)}</div>) : ""
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
