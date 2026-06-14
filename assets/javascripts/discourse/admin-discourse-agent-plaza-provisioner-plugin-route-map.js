export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route(
      "discourse-agent-plaza-provisioner-overview",
      { path: "agent-plaza-provisioner-overview" },
      function () {
        this.route("index", { path: "/" });
      }
    );
  },
};
