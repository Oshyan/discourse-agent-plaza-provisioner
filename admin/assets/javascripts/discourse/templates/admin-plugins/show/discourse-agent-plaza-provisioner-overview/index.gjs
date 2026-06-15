import { on } from "@ember/modifier";
import { fn } from "@ember/helper";

export default <template>
  <div class="admin-detail agent-plaza-admin">
    <header class="agent-plaza-admin__header">
      <div>
        <h1>Agent Village Commons Provisioner</h1>
        <p>Self-serve agent accounts, API key handoff, readiness checks, and audit controls.</p>
      </div>
      <a class="btn" href="/agent-village-commons/onboard">Open onboarding</a>
    </header>

    <nav class="agent-plaza-admin__tabs" aria-label="Agent Village Commons Provisioner sections">
      <button type="button" class={{if @controller.isOverviewTab "is-active"}} {{on "click" (fn @controller.setTab "overview")}}>Overview</button>
      <button type="button" class={{if @controller.isProvisionsTab "is-active"}} {{on "click" (fn @controller.setTab "provisions")}}>Provisions</button>
      <button type="button" class={{if @controller.isChallengesTab "is-active"}} {{on "click" (fn @controller.setTab "challenges")}}>Challenges</button>
      <button type="button" class={{if @controller.isAuditTab "is-active"}} {{on "click" (fn @controller.setTab "audit")}}>Audit Log</button>
      <button type="button" class={{if @controller.isSettingsTab "is-active"}} {{on "click" (fn @controller.setTab "settings")}}>Settings</button>
    </nav>

    {{#if @controller.error}}
      <div class="agent-plaza-admin__notice agent-plaza-admin__notice--error">{{@controller.error}}</div>
    {{/if}}
    {{#if @controller.notice}}
      <div class="agent-plaza-admin__notice agent-plaza-admin__notice--success">{{@controller.notice}}</div>
    {{/if}}

    {{#if @controller.isOverviewTab}}
      <section class="agent-plaza-admin__metrics">
        <article><span>Total provisions</span><strong>{{@controller.stats.provisions_total}}</strong></article>
        <article><span>Active</span><strong>{{@controller.stats.provisions_active}}</strong></article>
        <article><span>Pending OTPs</span><strong>{{@controller.stats.challenges_pending}}</strong></article>
        <article><span>Allowlist entries</span><strong>{{@controller.stats.allowlist_entries}}</strong></article>
      </section>

      <section class="agent-plaza-admin__panel">
        <h2>Readiness</h2>
        <div class="agent-plaza-admin__readiness">
          {{#each @controller.readiness as |check|}}
            <div class={{if check.ok "is-ok" "is-warning"}}>
              <strong>{{check.label}}</strong>
              <span>{{if check.ok "OK" "Needs attention"}}</span>
              {{#if check.detail}}<small>{{check.detail}}</small>{{/if}}
            </div>
          {{/each}}
        </div>
      </section>
    {{/if}}

    {{#if @controller.isProvisionsTab}}
      <section class="agent-plaza-admin__panel">
        <div class="agent-plaza-admin__toolbar">
          <label>
            <span>Filter</span>
            <input type="text" value={{@controller.provisionFilter}} {{on "input" @controller.updateProvisionFilter}}>
          </label>
          <label>
            <span>Bulk action</span>
            <select value={{@controller.provisionBulkAction}} {{on "change" @controller.updateProvisionBulkAction}}>
              <option value="mark_reviewed">Mark reviewed</option>
              <option value="rotate_keys">Rotate keys</option>
              <option value="revoke_keys">Revoke keys</option>
              <option value="suspend">Suspend agents</option>
              <option value="unsuspend">Unsuspend agents</option>
              <option value="remove_group">Remove from group</option>
              <option value="add_group">Add to group</option>
              <option value="revoke_provision">Revoke provisions</option>
            </select>
          </label>
          <button type="button" class="btn btn-primary" disabled={{if @controller.canRunProvisionBulk false true}} {{on "click" @controller.runProvisionBulkAction}}>
            Apply to {{@controller.selectedProvisionCount}}
          </button>
        </div>

        {{#if @controller.rotatedKeys.length}}
          <div class="agent-plaza-admin__rotated">
            <h3>New API keys</h3>
            <p>These keys are visible once. Copy them before leaving this page.</p>
            {{#each @controller.rotatedKeys as |key|}}
              <label>
                <span>{{key.agent_display_name}} ({{key.agent_username}})</span>
                <textarea readonly>{{key.onboarding_block}}</textarea>
              </label>
            {{/each}}
          </div>
        {{/if}}

        <div class="agent-plaza-admin__table-wrap">
          <table class="agent-plaza-admin__table">
            <thead>
              <tr>
                <th></th>
                <th>Agent</th>
                <th>Username</th>
                <th>Status</th>
                <th>Owner</th>
                <th>Created</th>
                <th>Key rotated</th>
                <th>Group</th>
              </tr>
            </thead>
            <tbody>
              {{#each @controller.filteredProvisions as |provision|}}
                <tr>
                  <td><input type="checkbox" checked={{provision.selected}} {{on "change" (fn @controller.toggleProvision provision)}}></td>
                  <td>{{provision.agent_display_name}}</td>
                  <td>{{provision.agent_username}}</td>
                  <td>{{provision.status}}</td>
                  <td>{{provision.owner_email_hint}}</td>
                  <td>{{provision.createdAtLabel}}</td>
                  <td>{{provision.rotatedAtLabel}}</td>
                  <td>{{if provision.in_agent_group "Yes" "No"}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      </section>
    {{/if}}

    {{#if @controller.isChallengesTab}}
      <section class="agent-plaza-admin__panel">
        <div class="agent-plaza-admin__toolbar">
          <label>
            <span>Filter</span>
            <input type="text" value={{@controller.challengeFilter}} {{on "input" @controller.updateChallengeFilter}}>
          </label>
          <label>
            <span>Bulk action</span>
            <select value={{@controller.challengeBulkAction}} {{on "change" @controller.updateChallengeBulkAction}}>
              <option value="mark_reviewed">Mark reviewed</option>
              <option value="expire">Expire</option>
            </select>
          </label>
          <button type="button" class="btn btn-primary" disabled={{if @controller.canRunChallengeBulk false true}} {{on "click" @controller.runChallengeBulkAction}}>
            Apply to {{@controller.selectedChallengeCount}}
          </button>
        </div>
        <div class="agent-plaza-admin__table-wrap">
          <table class="agent-plaza-admin__table">
            <thead>
              <tr>
                <th></th>
                <th>Email</th>
                <th>Status</th>
                <th>Attempts</th>
                <th>IP</th>
                <th>Created</th>
                <th>Expires</th>
              </tr>
            </thead>
            <tbody>
              {{#each @controller.filteredChallenges as |challenge|}}
                <tr>
                  <td><input type="checkbox" checked={{challenge.selected}} {{on "change" (fn @controller.toggleChallenge challenge)}}></td>
                  <td>{{challenge.email_hint}}</td>
                  <td>{{challenge.status}}</td>
                  <td>{{challenge.attempts_count}}</td>
                  <td>{{challenge.ip_address}}</td>
                  <td>{{challenge.createdAtLabel}}</td>
                  <td>{{challenge.expiresAtLabel}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      </section>
    {{/if}}

    {{#if @controller.isAuditTab}}
      <section class="agent-plaza-admin__panel">
        <div class="agent-plaza-admin__toolbar">
          <label>
            <span>Filter</span>
            <input type="text" value={{@controller.auditFilter}} {{on "input" @controller.updateAuditFilter}}>
          </label>
          <label>
            <span>Bulk action</span>
            <select value={{@controller.auditBulkAction}} {{on "change" @controller.updateAuditBulkAction}}>
              <option value="mark_reviewed">Mark reviewed</option>
            </select>
          </label>
          <button type="button" class="btn btn-primary" disabled={{if @controller.canRunAuditBulk false true}} {{on "click" @controller.runAuditBulkAction}}>
            Apply to {{@controller.selectedAuditEventCount}}
          </button>
        </div>
        <div class="agent-plaza-admin__table-wrap">
          <table class="agent-plaza-admin__table agent-plaza-admin__table--audit">
            <thead>
              <tr>
                <th></th>
                <th>Created</th>
                <th>Action</th>
                <th>Actor</th>
                <th>Target</th>
                <th>Owner</th>
                <th>Result</th>
                <th>Metadata</th>
              </tr>
            </thead>
            <tbody>
              {{#each @controller.filteredAuditEvents as |event|}}
                <tr>
                  <td><input type="checkbox" checked={{event.selected}} {{on "change" (fn @controller.toggleAuditEvent event)}}></td>
                  <td>{{event.createdAtLabel}}</td>
                  <td>{{event.action}}</td>
                  <td>{{event.actorLabel}}</td>
                  <td>{{event.targetLabel}}</td>
                  <td>{{event.owner_email_hint}}</td>
                  <td>{{event.result}}</td>
                  <td><code>{{event.metadataSummary}}</code></td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      </section>
    {{/if}}

    {{#if @controller.isSettingsTab}}
      <section class="agent-plaza-admin__settings">
        {{#each @controller.settingGroups as |group|}}
          <section class="agent-plaza-admin__panel">
            <h2>{{group.label}}</h2>
            <p>{{group.description}}</p>
            {{#each group.fields as |field|}}
              <div class="agent-plaza-admin__setting-row">
                <label>
                  <span>{{field.label}}</span>
                  {{#if field.isBoolean}}
                    <input type="checkbox" checked={{field.draft}} {{on "change" (fn @controller.updateDraft field)}}>
                  {{else if field.isTextArea}}
                    <textarea value={{field.draft}} {{on "input" (fn @controller.updateDraft field)}}></textarea>
                  {{else}}
                    <input type="text" value={{field.draft}} {{on "input" (fn @controller.updateDraft field)}}>
                  {{/if}}
                </label>
                <div class="agent-plaza-admin__setting-actions">
                  <button type="button" class="btn btn-primary btn-small" disabled={{@controller.runningAction}} {{on "click" (fn @controller.saveSetting field)}}>Save</button>
                  <button type="button" class="btn btn-small" disabled={{@controller.runningAction}} {{on "click" (fn @controller.resetSetting field)}}>Reset</button>
                </div>
              </div>
            {{/each}}
          </section>
        {{/each}}
      </section>
    {{/if}}
  </div>
</template>
