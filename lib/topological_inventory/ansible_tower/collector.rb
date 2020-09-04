require "topological_inventory/ansible_tower/logging"
require "topological_inventory/providers/common/collector"
require "topological_inventory/ansible_tower/connection_manager"
require "topological_inventory/ansible_tower/parser"
require "topological_inventory/ansible_tower/iterator"

module TopologicalInventory
  module AnsibleTower
    class Collector < TopologicalInventory::Providers::Common::Collector
      include Logging

      require "topological_inventory/ansible_tower/collector/service_catalog"
      include TopologicalInventory::AnsibleTower::Collector::ServiceCatalog

      def initialize(source, metrics, default_limit: 100, poll_time: 60, standalone_mode: true)
        super(source, :default_limit => default_limit, :poll_time => poll_time, :standalone_mode => standalone_mode)
        self.connection_manager = TopologicalInventory::AnsibleTower::ConnectionManager.new(source)
        self.metrics            = metrics
        self.tower_hostname     = ''
      end

      def collect!
        until finished?
          ensure_collector_threads

          wait_for_collected_data

          standalone_mode ? sleep(poll_time) : stop
        end
      end

      private

      attr_accessor :connection_manager, :metrics, :tower_hostname

      def wait_for_collected_data
        collector_threads.each_value(&:join)
      end

      def endpoint_types
        %w[service_catalog]
      end

      def service_catalog_entity_types
        %w[service_inventories
           service_offerings
           service_offering_nodes
           service_credentials
           service_credential_types]
      end

      def inventory_name
        "AnsibleTower"
      end
    end
  end
end
