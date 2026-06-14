# frozen_string_literal: true

module ::AgentPlazaProvisioner
  class Engine < ::Rails::Engine
    engine_name "agent_plaza_provisioner"
    isolate_namespace AgentPlazaProvisioner
  end
end
