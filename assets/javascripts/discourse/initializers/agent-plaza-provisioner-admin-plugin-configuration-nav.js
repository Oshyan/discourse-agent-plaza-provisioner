import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "agent-plaza-provisioner-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon("discourse-agent-plaza-provisioner", "robot");
      api.addAdminPluginConfigurationNav("discourse-agent-plaza-provisioner", [
        {
          label: "agent_plaza_provisioner.admin.overview.title",
          route: "adminPlugins.show.discourse-agent-plaza-provisioner-overview.index",
          description: "agent_plaza_provisioner.admin.overview.description",
        },
      ]);
    });
  },
};
