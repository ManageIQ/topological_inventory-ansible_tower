require "topological_inventory/ansible_tower/connection"
require "receptor_controller-client"
require "topological_inventory/ansible_tower/receptor/api_client"

module TopologicalInventory::AnsibleTower
  class ConnectionManager
    include Logging

    @@sync = Mutex.new
    @@receptor_client = nil

    def connect(base_url, username, password,
                verify_ssl: ::OpenSSL::SSL::VERIFY_NONE,
                receptor_node: nil, account_number: nil)
      if receptor_node && account_number
        receptor_api_client(base_url, username, password, receptor_node, account_number, :verify_ssl => verify_ssl)
      else
        ansible_tower_api_client(base_url, username, password, :verify_ssl => verify_ssl)
      end
    end

    def receptor_client
      @@sync.synchronize do
        return @@receptor_client if @@receptor_client.present?

        @@receptor_client = ReceptorController::Client.new(:logger => logger)
        @@receptor_client.start # TODO: Stop it somewhere
      end
      @@receptor_client
    end

    private

    def receptor_api_client(base_url, username, password, receptor_node, account_number, verify_ssl:)
      TopologicalInventory::AnsibleTower::Receptor::ApiClient.new(
        base_url, username, password, receptor_client, receptor_node, account_number,
        :verify_ssl => verify_ssl,
        )
    end

    def ansible_tower_api_client(base_url, username, password, verify_ssl:)
      TopologicalInventory::AnsibleTower::Connection.new.connect(
        base_url, username, password,
        :verify_ssl => verify_ssl
      )
    end
  end
end