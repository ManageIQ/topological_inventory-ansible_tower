require "topological_inventory/ansible_tower/collector"

module TopologicalInventory::AnsibleTower
  module Cloud
    class Collector < TopologicalInventory::AnsibleTower::Collector
      def initialize(source, tower_hostname, tower_user, tower_passwd, metrics,
                     default_limit: 100, standalone_mode: true)
        super(source, metrics, :default_limit => default_limit, :standalone_mode => standalone_mode)

        self.tower_hostname = tower_hostname
        self.tower_user     = tower_user
        self.tower_passwd   = tower_passwd
      end

      private

      attr_accessor :tower_user, :tower_passwd

      # Connection to endpoint (for each entity type the same)
      def connection_for_entity_type(_entity_type)
        connection_manager.connect(:base_url => tower_hostname, :username => tower_user, :password => tower_passwd)
      end

      # Thread's main for collecting one entity type's data
      def collector_thread(connection, entity_type)
        refresh_state_uuid, refresh_state_started_at, refresh_state_part_collected_at = SecureRandom.uuid, Time.now.utc, nil

        logger.collecting(:start, source, entity_type, refresh_state_uuid)
        parser = TopologicalInventory::AnsibleTower::Parser.new(:tower_url => tower_hostname)

        cnt, sweep_scope, total_parts = 0, Set.new, 0
        # each on ansible_tower_client's enumeration makes pagination requests by itself
        opts = {:page_size => limits[entity_type]}
        opts[:modified__gt] = last_modified_at if scheduler.do_partial_refresh?(source)

        send("get_#{entity_type}", connection, opts).each do |entity|
          refresh_state_part_collected_at = Time.now.utc
          cnt += 1

          parser.send("parse_#{entity_type.singularize}", entity)

          if cnt >= limits[entity_type]
            total_parts += 1
            refresh_state_part_uuid = SecureRandom.uuid
            save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid, refresh_state_part_collected_at)
            sweep_scope.merge(parser.collections.values.map(&:name))
            # re-init
            parser = TopologicalInventory::AnsibleTower::Parser.new(:tower_url => tower_hostname)
            cnt    = 0
          end
        end

        if parser.collections.values.present?
          total_parts += 1
          refresh_state_part_uuid = SecureRandom.uuid
          save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid, refresh_state_part_collected_at)
          sweep_scope.merge(parser.collections.values.map(&:name))
        end
        logger.collecting(:finish, source, entity_type, refresh_state_uuid, total_parts)

        unless scheduler.do_partial_refresh?(source)
          # Sweeping (archiving) inactive records
          sweep_scope = sweep_scope.to_a
          logger.sweeping(:start, source, sweep_scope, refresh_state_uuid)
          sweep_inventory(inventory_name, schema_name, refresh_state_uuid, total_parts, sweep_scope, refresh_state_started_at)
          logger.sweeping(:finish, source, sweep_scope, refresh_state_uuid)
        end
      rescue => e
        metrics.record_error
        logger.collecting_error(source, entity_type, refresh_state_uuid, e)
      end
    end
  end
end
