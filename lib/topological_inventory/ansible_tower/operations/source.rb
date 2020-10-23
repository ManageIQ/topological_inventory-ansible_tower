require "topological_inventory/ansible_tower/logging"
require "topological_inventory/providers/common/operations/source"
require "topological_inventory/ansible_tower/connection_manager"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Source < TopologicalInventory::Providers::Common::Operations::Source
        include Logging

        private

        def connection_check
          connection = ::TopologicalInventory::AnsibleTower::ConnectionManager.new(source_id).connect(
            :base_url       => full_hostname(endpoint),
            :username       => authentication.try(:username),
            :password       => authentication.try(:password),
            :receptor_node  => endpoint.receptor_node,
            :account_number => account_number
          )
          connection.api.version

          [STATUS_AVAILABLE, nil]
        rescue => e
          logger.availability_check("Failed to connect to Source id:#{source_id} - #{e.message}", :error)
          [STATUS_UNAVAILABLE, e.message]
        end
      end
    end
  end
end
