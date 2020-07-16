require "concurrent"
require "topological_inventory/ansible_tower/logging"
require "pry-byebug"
module TopologicalInventory::AnsibleTower
  module Receptor
    class AsyncReceiver
      include Logging

      attr_accessor :collector, :transformation
      attr_reader :connection, :entity_type, :refresh_state_uuid, :refresh_state_started_at, :sweep_scope, :total_parts

      def initialize(collector, connection, entity_type, refresh_state_uuid, refresh_state_started_at)
        self.collector = collector
        self.connection = connection
        self.entity_type = entity_type
        self.refresh_state_uuid = refresh_state_uuid
        self.refresh_state_started_at = refresh_state_started_at
        self.sweep_scope = Concurrent::Set.new
        self.total_parts = Concurrent::AtomicFixnum.new
        self.transformation = nil
      end

      def on_success(msg_id, entity)
        # TODO: without tower hostname, it's not possible to construct job URL
        parser = TopologicalInventory::AnsibleTower::Parser.new(tower_url: 'https://tower.example.com')
        parsable_entity = transformation ? transformation.call(entity) : entity
        parser.send("parse_#{entity_type.singularize}", parsable_entity)

        total_parts.increment
        collector.async_save_inventory(refresh_state_uuid, parser)
        sweep_scope.merge(parser.collections.values.map(&:name))
      rescue ReceptorController::Client::Error => exception
        # Exceptions can be raised by synchronous requests inside transformation
        # TODO: Transform to async
        msg = "[ERROR] Collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}); MSG ID: #{msg_id}, "
        msg += ":message => #{exception.message}\n#{exception.backtrace.join("\n")}"
        logger.error(msg)
      end

      def on_error(msg_id, code, response)
        logger.error("[ERROR] Collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}); MSG ID: #{msg_id}, CODE: #{code}, RESPONSE: #{response}")
      end

      def on_timeout(msg_id)
        logger.error("[ERROR] Timeout when collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}; MSG ID: #{msg_id}, ")
      end

      def on_eof(_msg_id)
        collector.async_collecting_finished(entity_type, refresh_state_uuid, total_parts.value)

        collector.async_sweep_inventory(refresh_state_uuid, sweep_scope.to_a, total_parts.value, refresh_state_started_at)
      end

      private

      attr_writer :connection, :entity_type, :refresh_state_uuid, :refresh_state_started_at, :sweep_scope, :total_parts
    end
  end
end
