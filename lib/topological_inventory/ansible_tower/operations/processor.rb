require "topological_inventory/providers/common"
require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/operations/service_offering"
require "topological_inventory/ansible_tower/operations/service_plan"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Processor < TopologicalInventory::Providers::Common::Operations::Processor
        include Logging

        protected

        def operation_model
          "#{Operations}::#{model}".safe_constantize
        end
      end
    end
  end
end
