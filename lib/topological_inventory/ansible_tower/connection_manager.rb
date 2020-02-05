require "topological_inventory/ansible_tower/connection"
require "topological_inventory/ansible_tower/receptor/api_client"

module TopologicalInventory::AnsibleTower
  class ConnectionManager
    @@sync = Mutex.new
    @@receptor_response_worker = nil

    def connect(base_url, username, password,
                verify_ssl: ::OpenSSL::SSL::VERIFY_NONE,
                queue_host: nil, queue_port: nil,
                receptor_id: nil, receptor_base_url: nil, account_number: nil)
      if receptor_id && receptor_base_url && account_number
        receptor_api_client(base_url, username, password, receptor_id, receptor_base_url, account_number, queue_host, queue_port, :verify_ssl => verify_ssl)
      else
        ansible_tower_api_client(base_url, username, password, :verify_ssl => verify_ssl)
      end
    end

    private

    def receptor_response_worker(queue_host, queue_port)
      @@sync.synchronize do
        @@receptor_response_worker ||= TopologicalInventory::AnsibleTower::Receptor::ResponseWorker.new(queue_host, queue_port)
        @@receptor_response_worker.start unless @@receptor_response_worker.started?
      end
      @@receptor_response_worker
    end

    def receptor_api_client(base_url, username, password, receptor_id, receptor_base_url, account_number, queue_host, queue_port, verify_ssl:)
      account_number = '0000001' # TODO: for now!
      TopologicalInventory::AnsibleTower::Receptor::ApiClient.new(
        base_url, username, password, receptor_id, receptor_base_url, account_number,
        receptor_response_worker(queue_host, queue_port),
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