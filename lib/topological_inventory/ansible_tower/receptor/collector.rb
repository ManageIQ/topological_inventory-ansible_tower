require "topological_inventory/ansible_tower/collector"
require "topological_inventory/ansible_tower/receptor/async_receiver"

module TopologicalInventory::AnsibleTower
  module Receptor
    class Collector < TopologicalInventory::AnsibleTower::Collector
      def initialize(source, receptor_node, account_number, metrics, default_limit: 100, standalone_mode: true)
        super(source, metrics, :default_limit => default_limit, :standalone_mode => standalone_mode)
        self.account_number = account_number # eq Tenant.external_tenant or account_number in x-rh-identity
        self.entity_types_collected_cnt = Concurrent::AtomicFixnum.new(0)
        self.last_response_at = nil
        self.max_wait_sync_threshold = ENV['RECEPTOR_COLLECTOR_MAX_WAIT_SYNC'] || 10
        self.receptor_node  = receptor_node
        self.tower_hostname = "receptor://#{receptor_node}" # For logging
      end

      def collect!
        TopologicalInventory::AnsibleTower::ConnectionManager.start_receptor_client
        super
      end

      def connection_for_entity_type(_entity_type)
        connection_manager.connect(:account_number => account_number,
                                   :receptor_node  => receptor_node)
      end

      def collector_thread(connection, entity_type)
        refresh_state_uuid, refresh_state_started_at = SecureRandom.uuid, Time.now.utc

        logger.collecting(:start, source, entity_type, refresh_state_uuid)

        sweeping_disabled = scheduler.do_partial_refresh?(source) && last_modified_at.present?
        receiver = AsyncReceiver.new(self,
                                     connection,
                                     entity_type,
                                     refresh_state_uuid,
                                     refresh_state_started_at,
                                     :sweeping_enabled => !sweeping_disabled)

        # opts = {:fetch_all_pages => true, :accept_encoding => 'gzip', :apply_filter => nil}
        receptor_params = {:accept_encoding => 'gzip', :fetch_all_pages => true}
        query_params    = {:page_size => limits[entity_type]}
        query_params[:modified__gt] = last_modified_at if scheduler.do_partial_refresh?(source)
        send("get_#{entity_type}", connection, query_params,
             :on_premise => true, :receptor_receiver => receiver, :receptor_params => receptor_params)
      end

      def async_collecting_finished(entity_type, refresh_state_uuid, total_parts)
        logger.collecting(:finish, source, entity_type, refresh_state_uuid, total_parts)
      end

      def async_save_inventory(refresh_state_uuid, parser)
        refresh_state_part_collected_at = Time.now.utc
        refresh_state_part_uuid = SecureRandom.uuid
        save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid, refresh_state_part_collected_at)
      end

      # Not called by partial refresh
      def async_sweep_inventory(refresh_state_uuid, sweep_scope, total_parts, refresh_state_started_at)
        logger.sweeping(:start, source, sweep_scope, refresh_state_uuid)

        logger.debug("Received #{entity_types_collected_cnt.value} of #{service_catalog_entity_types.size} complete responses")

        sweep_inventory(inventory_name, schema_name, refresh_state_uuid, total_parts, sweep_scope, refresh_state_started_at)
        entity_types_collected_cnt.increment # Real finish of entity_type's requests

        logger.sweeping(:finish, source, sweep_scope, refresh_state_uuid)
      end

      def response_received!
        self.last_response_at = Time.now.utc
      end

      private

      attr_accessor :account_number, :entity_types_collected_cnt, :last_response_at, :max_wait_sync_threshold,
                    :receptor_node, :refresh_started_at

      def start_collector_threads
        self.last_response_at = nil
        self.refresh_started_at = Time.now.utc
        entity_types_collected_cnt.value = 0

        super
      end

      def wait_for_collected_data
        super

        # Wait until all async responses are sent
        while entity_types_collected_cnt.value < service_catalog_entity_types.size
          if last_response_at.nil?
            if refresh_started_at >= max_wait_sync_threshold.minutes.ago.utc
              logger.warn("[ASYNC] Collector for source_uid: #{source}: No response received since #{refresh_started_at}")
              sleep(10)
            else
              logger.error("[ASYNC] Collector for source_uid: #{source}: No responses received. Waiting finished")
              break
            end
          elsif last_response_at >= (ReceptorController::Client::Configuration.default.response_timeout + 10.seconds).ago.utc
            sleep(1) # standard situation
          elsif last_response_at >= max_wait_sync_threshold.minutes.ago.utc
            # Either error in collector or big kafka lag from receptor
            logger.warn("[ASYNC] Collector for source_uid: #{source}: Last response received at #{last_response_at}")
            sleep(10)
          else # last_response_at < max_wait_sync_threshold.minutes.ago
            logger.error("[ASYNC] Collector for source_uid: #{source}: Only #{entity_types_collected_cnt.value} of #{service_catalog_entity_types.size} entity types were successfully received. Waiting finished")
            break
          end
        end

        logger.info("Total complete entity_types received: #{entity_types_collected_cnt.value} of #{service_catalog_entity_types.size}")
      end
    end
  end
end
