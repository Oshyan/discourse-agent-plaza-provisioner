import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";

function errorMessage(error, fallback = "Action failed.") {
  const responseJSON = error?.jqXHR?.responseJSON || error?.responseJSON;
  const errors = responseJSON?.errors;

  if (Array.isArray(errors) && errors.length > 0) {
    return errors.join(" ");
  }

  return responseJSON?.error || responseJSON?.message || fallback;
}

function formatDate(value) {
  if (!value) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

export default class AdminPluginsShowDiscourseAgentPlazaProvisionerOverviewIndexController extends Controller {
  @tracked activeTab = "overview";
  @tracked stats = {};
  @tracked readiness = [];
  @tracked provisions = [];
  @tracked challenges = [];
  @tracked auditEvents = [];
  @tracked settings = {};
  @tracked categories = [];
  @tracked groups = [];
  @tracked drafts = {};
  @tracked notice = "";
  @tracked error = "";
  @tracked provisionFilter = "";
  @tracked challengeFilter = "";
  @tracked auditFilter = "";
  @tracked selectedProvisionIds = [];
  @tracked selectedChallengeIds = [];
  @tracked selectedAuditEventIds = [];
  @tracked provisionBulkAction = "mark_reviewed";
  @tracked challengeBulkAction = "mark_reviewed";
  @tracked auditBulkAction = "mark_reviewed";
  @tracked runningAction = false;
  @tracked rotatedKeys = [];

  syncFromModel(model) {
    this.stats = model?.stats || {};
    this.readiness = model?.readiness || [];
    this.provisions = model?.provisions || [];
    this.challenges = model?.challenges || [];
    this.auditEvents = model?.audit_events || [];
    this.settings = model?.settings || {};
    this.categories = model?.categories || [];
    this.groups = model?.groups || [];
    this.syncDrafts();
    this.notice = "";
    this.error = "";
  }

  syncDrafts() {
    const next = {};
    (this.settings.groups || []).forEach((group) => {
      group.fields.forEach((field) => {
        next[field.name] = field.value;
      });
    });
    this.drafts = next;
  }

  get isOverviewTab() {
    return this.activeTab === "overview";
  }

  get isProvisionsTab() {
    return this.activeTab === "provisions";
  }

  get isChallengesTab() {
    return this.activeTab === "challenges";
  }

  get isAuditTab() {
    return this.activeTab === "audit";
  }

  get isSettingsTab() {
    return this.activeTab === "settings";
  }

  get decoratedProvisions() {
    return this.provisions.map((provision) => ({
      ...provision,
      selected: this.selectedProvisionIds.includes(provision.id),
      createdAtLabel: formatDate(provision.created_at),
      rotatedAtLabel: formatDate(provision.last_key_rotated_at),
      searchText: [
        provision.agent_display_name,
        provision.agent_username,
        provision.status,
        provision.owner_email_hint,
      ].filter(Boolean).join(" ").toLowerCase(),
    }));
  }

  get filteredProvisions() {
    const query = this.provisionFilter.trim().toLowerCase();
    return query ? this.decoratedProvisions.filter((row) => row.searchText.includes(query)) : this.decoratedProvisions;
  }

  get decoratedChallenges() {
    return this.challenges.map((challenge) => ({
      ...challenge,
      selected: this.selectedChallengeIds.includes(challenge.id),
      createdAtLabel: formatDate(challenge.created_at),
      expiresAtLabel: formatDate(challenge.expires_at),
      searchText: [
        challenge.email_hint,
        challenge.status,
        challenge.ip_address,
        challenge.user_agent,
      ].filter(Boolean).join(" ").toLowerCase(),
    }));
  }

  get filteredChallenges() {
    const query = this.challengeFilter.trim().toLowerCase();
    return query ? this.decoratedChallenges.filter((row) => row.searchText.includes(query)) : this.decoratedChallenges;
  }

  get decoratedAuditEvents() {
    return this.auditEvents.map((event) => ({
      ...event,
      selected: this.selectedAuditEventIds.includes(event.id),
      createdAtLabel: formatDate(event.created_at),
      actorLabel: event.actor?.username || event.actor_type,
      targetLabel: event.target_user?.username || "",
      metadataSummary: JSON.stringify(event.metadata || {}),
      searchText: [
        event.action,
        event.actor_type,
        event.actor?.username,
        event.target_user?.username,
        event.owner_email_hint,
        event.ip_address,
        event.result,
        JSON.stringify(event.metadata || {}),
      ].filter(Boolean).join(" ").toLowerCase(),
    }));
  }

  get filteredAuditEvents() {
    const query = this.auditFilter.trim().toLowerCase();
    return query ? this.decoratedAuditEvents.filter((row) => row.searchText.includes(query)) : this.decoratedAuditEvents;
  }

  get selectedProvisionCount() {
    return this.selectedProvisionIds.length;
  }

  get selectedChallengeCount() {
    return this.selectedChallengeIds.length;
  }

  get selectedAuditEventCount() {
    return this.selectedAuditEventIds.length;
  }

  get canRunProvisionBulk() {
    return this.selectedProvisionCount > 0 && !this.runningAction;
  }

  get canRunChallengeBulk() {
    return this.selectedChallengeCount > 0 && !this.runningAction;
  }

  get canRunAuditBulk() {
    return this.selectedAuditEventCount > 0 && !this.runningAction;
  }

  get settingGroups() {
    return (this.settings.groups || []).map((group) => ({
      ...group,
      fields: group.fields.map((field) => ({
        ...field,
        draft: this.drafts[field.name],
        isBoolean: field.type === "boolean",
        isTextArea: field.type === "list" || field.type === "text_area",
      })),
    }));
  }

  @action
  setTab(tab) {
    this.activeTab = tab;
    this.notice = "";
    this.error = "";
    this.rotatedKeys = [];
  }

  @action
  updateProvisionFilter(event) {
    this.provisionFilter = event.target.value;
  }

  @action
  updateChallengeFilter(event) {
    this.challengeFilter = event.target.value;
  }

  @action
  updateAuditFilter(event) {
    this.auditFilter = event.target.value;
  }

  @action
  updateProvisionBulkAction(event) {
    this.provisionBulkAction = event.target.value;
  }

  @action
  updateChallengeBulkAction(event) {
    this.challengeBulkAction = event.target.value;
  }

  @action
  updateAuditBulkAction(event) {
    this.auditBulkAction = event.target.value;
  }

  @action
  toggleProvision(provision, event) {
    this.selectedProvisionIds = event.target.checked
      ? [...new Set([...this.selectedProvisionIds, provision.id])]
      : this.selectedProvisionIds.filter((id) => id !== provision.id);
  }

  @action
  toggleChallenge(challenge, event) {
    this.selectedChallengeIds = event.target.checked
      ? [...new Set([...this.selectedChallengeIds, challenge.id])]
      : this.selectedChallengeIds.filter((id) => id !== challenge.id);
  }

  @action
  toggleAuditEvent(auditEvent, event) {
    this.selectedAuditEventIds = event.target.checked
      ? [...new Set([...this.selectedAuditEventIds, auditEvent.id])]
      : this.selectedAuditEventIds.filter((id) => id !== auditEvent.id);
  }

  @action
  async runProvisionBulkAction() {
    if (!this.canRunProvisionBulk) {
      return;
    }

    const destructive = ["revoke_keys", "suspend", "remove_group", "revoke_provision"].includes(this.provisionBulkAction);
    if (destructive && !window.confirm(`Apply ${this.provisionBulkAction} to ${this.selectedProvisionCount} provision(s)?`)) {
      return;
    }

    this.runningAction = true;
    this.notice = "";
    this.error = "";
    this.rotatedKeys = [];

    try {
      const response = await ajax("/admin/plugins/agent-plaza-provisioner/provisions/bulk.json", {
        type: "PUT",
        data: {
          provision_ids: this.selectedProvisionIds,
          bulk_action: this.provisionBulkAction,
        },
      });
      this.provisions = response.provisions || this.provisions;
      this.rotatedKeys = response.rotated_keys || [];
      this.selectedProvisionIds = [];
      this.notice = "Provision action completed.";
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.runningAction = false;
    }
  }

  @action
  async runChallengeBulkAction() {
    if (!this.canRunChallengeBulk) {
      return;
    }

    this.runningAction = true;
    this.notice = "";
    this.error = "";

    try {
      const response = await ajax("/admin/plugins/agent-plaza-provisioner/challenges/bulk.json", {
        type: "PUT",
        data: {
          challenge_ids: this.selectedChallengeIds,
          bulk_action: this.challengeBulkAction,
        },
      });
      this.challenges = response.challenges || this.challenges;
      this.selectedChallengeIds = [];
      this.notice = "Challenge action completed.";
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.runningAction = false;
    }
  }

  @action
  async runAuditBulkAction() {
    if (!this.canRunAuditBulk) {
      return;
    }

    this.runningAction = true;
    this.notice = "";
    this.error = "";

    try {
      const response = await ajax("/admin/plugins/agent-plaza-provisioner/audit-events/bulk.json", {
        type: "PUT",
        data: {
          audit_event_ids: this.selectedAuditEventIds,
          bulk_action: this.auditBulkAction,
        },
      });
      this.auditEvents = response.audit_events || this.auditEvents;
      this.selectedAuditEventIds = [];
      this.notice = "Audit action completed.";
    } catch (error) {
      this.error = errorMessage(error);
    } finally {
      this.runningAction = false;
    }
  }

  @action
  updateDraft(field, event) {
    const value = field.isBoolean ? event.target.checked : event.target.value;
    this.drafts = { ...this.drafts, [field.name]: value };
  }

  @action
  async saveSetting(field) {
    this.runningAction = true;
    this.notice = "";
    this.error = "";

    try {
      const response = await ajax(`/admin/plugins/agent-plaza-provisioner/settings/${field.name}.json`, {
        type: "PUT",
        data: { value: this.drafts[field.name] },
      });
      this.settings = response.settings || this.settings;
      this.readiness = response.readiness || this.readiness;
      this.syncDrafts();
      this.notice = "Setting saved.";
    } catch (error) {
      this.error = errorMessage(error, "Setting could not be saved.");
    } finally {
      this.runningAction = false;
    }
  }

  @action
  async resetSetting(field) {
    this.runningAction = true;
    this.notice = "";
    this.error = "";

    try {
      const response = await ajax(`/admin/plugins/agent-plaza-provisioner/settings/${field.name}.json`, {
        type: "DELETE",
      });
      this.settings = response.settings || this.settings;
      this.readiness = response.readiness || this.readiness;
      this.syncDrafts();
      this.notice = "Setting reset.";
    } catch (error) {
      this.error = errorMessage(error, "Setting could not be reset.");
    } finally {
      this.runningAction = false;
    }
  }
}
