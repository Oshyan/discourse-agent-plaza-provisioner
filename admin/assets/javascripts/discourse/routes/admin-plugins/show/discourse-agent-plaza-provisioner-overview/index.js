import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowDiscourseAgentPlazaProvisionerOverviewIndexRoute extends DiscourseRoute {
  async model() {
    return await ajax("/admin/plugins/agent-plaza-provisioner/overview.json");
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.syncFromModel(model);
  }
}
