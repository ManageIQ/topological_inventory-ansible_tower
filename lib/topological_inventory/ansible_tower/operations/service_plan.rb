require "topological_inventory/providers/common/operations/service_plan"
require "topological_inventory/ansible_tower/operations/core/ansible_tower_client"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class ServicePlan < TopologicalInventory::Providers::Common::Operations::ServicePlan
        include Logging

        def endpoint_client(source_id, task_id, identity)
          Core::AnsibleTowerClient.new(source_id, task_id, identity)
        end
      end
    end
  end
end
