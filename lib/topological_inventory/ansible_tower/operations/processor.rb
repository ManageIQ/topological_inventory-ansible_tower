require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/operations/service_offering"
require "topological_inventory/ansible_tower/operations/source"
require "topological_inventory/providers/common/operations/processor"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Processor < TopologicalInventory::Providers::Common::Operations::Processor
        include Logging

        def operation_class
          "#{Operations}::#{model}".safe_constantize
        end
      end
    end
  end
end
