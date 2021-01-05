require 'time'
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

      def initialize(source, metrics,
                     default_limit: 100,
                     poll_time: scheduler.partial_refresh_frequency,
                     standalone_mode: true)
        super(source, :default_limit => default_limit, :poll_time => poll_time, :standalone_mode => standalone_mode)
        self.connection_manager = TopologicalInventory::AnsibleTower::ConnectionManager.new(source)
        self.metrics            = metrics
        self.tower_hostname     = ''
      end

      def collect!
        until finished?
          if scheduler.do_refresh?(source)
            refresh_type = refresh_started

            ensure_collector_threads
            wait_for_collected_data

            refresh_finished(refresh_type)
          end

          standalone_mode ? sleep(poll_time) : stop
        end
      end

      # AsyncReceiver method that needs to be on EVERY instance of collector for receptor.
      def response_received!
      end

      private

      attr_accessor :connection_manager, :metrics, :tower_hostname

      def scheduler
        require "topological_inventory/ansible_tower/collector/scheduler"
        TopologicalInventory::AnsibleTower::Collector::Scheduler.default
      end

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

      def refresh_started
        msg          = "Refresh started | :type => "
        refresh_type = if scheduler.do_partial_refresh?(source)
                         scheduler.partial_refresh_started!(source)
                         msg += ":partial_refresh, :from => #{last_modified_at}"
                         :partial_refresh
                       else
                         scheduler.full_refresh_started!(source)
                         msg += ':full_refresh'
                         :full_refresh
                       end
        logger.info("#{msg}, :source_uid => #{source}")

        refresh_type
      end

      def refresh_finished(refresh_type)
        msg = "Refresh finished | :type => #{refresh_type}"
        if refresh_type == :partial_refresh
          scheduler.partial_refresh_finished!(source)
        else
          scheduler.full_refresh_finished!(source)
        end
        logger.info("#{msg}, :source_uid => #{source}")
      rescue => e
        logger.error("#{msg} | #{e.message}\n#{e.backtrace.join('\n')}")
        metrics&.record_error
      end

      # Last time of partial refresh, used in API calls
      def last_modified_at
        if scheduler.do_partial_refresh?(source)
          scheduler.last_partial_refresh_at(source)&.iso8601
        end
      end
    end
  end
end
