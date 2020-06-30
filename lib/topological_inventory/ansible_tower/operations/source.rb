require "topological_inventory/ansible_tower/logging"
require "topological_inventory/providers/common/operations/source"
require "topological_inventory/ansible_tower/connection"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Source < TopologicalInventory::Providers::Common::Operations::Source
        include Logging

        private

        def connection_check
          if endpoint.receptor_node.present?
            # TODO: this will change when using the new plugin.
            connection = connection_manager.connect(full_hostname(endpoint), authentication.username, authentication.password,
                                       :receptor_node => endpoint.receptor_node,
                                       #:account_number => "1460290",
                                       :account_number => "0000001",
                                       :verify_ssl => 0)

            connection.get("/api/v2/ping/")
          else
            connection = connection_manager.connect(full_hostname(endpoint), authentication.username, authentication.password)
            connection.api.version
          end

          [STATUS_AVAILABLE, nil]
        rescue => e
          logger.availability_check("Failed to connect to Source id:#{source_id} - #{e.message}", :error)
          [STATUS_UNAVAILABLE, e.message]
        end

        def full_hostname(endpoint)
          endpoint.host.tap { |host| host << ":#{endpoint.port}" if endpoint.port }
        end

        def connection_manager
          @connection_manager ||= TopologicalInventory::AnsibleTower::ConnectionManager.new
        end
      end
    end
  end
end
