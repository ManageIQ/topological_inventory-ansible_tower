require "concurrent"
require "topological_inventory/ansible_tower/logging"

module TopologicalInventory::AnsibleTower
  module Receptor
    class AsyncReceiver
      include Logging

      # Number of expected 'on_eof' calls
      attr_accessor :async_requests_remaining
      attr_accessor :collector
      # Lambda block for transformation from collected data to parsable data
      attr_accessor :transformation
      attr_reader :connection, :entity_type, :refresh_state_uuid, :refresh_state_started_at, :sweeping_enabled, :sweep_scope, :total_parts

      delegate :metrics, :to => :collector

      def initialize(collector, connection, entity_type, refresh_state_uuid, refresh_state_started_at, sweeping_enabled: true)
        self.async_requests_remaining = Concurrent::AtomicFixnum.new
        self.collector = collector
        self.connection = connection
        self.entity_type = entity_type
        self.refresh_state_uuid = refresh_state_uuid
        self.refresh_state_started_at = refresh_state_started_at
        self.sweeping_enabled = Concurrent::AtomicBoolean.new(sweeping_enabled)
        self.sweep_scope = Concurrent::Set.new
        self.total_parts = Concurrent::AtomicFixnum.new
        self.transformation = nil
      end

      def on_success(msg_id, entities)
        collector.response_received!

        # TODO: without tower hostname, it's not possible to construct job URL
        parser = TopologicalInventory::AnsibleTower::Parser.new(:tower_url => 'https://tower.example.com')
        entities.each do |entity|
          # Exceptions can be raised by synchronous requests inside transformation
          parsable_entity = transformation ? transformation.call(entity) : entity
          parser.send("parse_#{entity_type.singularize}", parsable_entity)
        rescue ReceptorController::Client::Error => exception
          # Archiving when error occurred isn't wanted, skipping sweep
          sweeping_enabled.value = false

          msg = "[ERROR] Collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}); MSG ID: #{msg_id}, "
          msg += ":message => #{exception.message}\n#{exception.backtrace.join("\n")}"
          logger.error(msg)
          metrics&.record_error(:receptor_error_response)
        ensure
          collector.response_received!
        end

        if entities.present?
          total_parts.increment
          collector.async_save_inventory(entity_type, refresh_state_uuid, parser)
          sweep_scope.merge(parser.collections.values.map(&:name))
        end
      rescue
        sweeping_enabled.value = false
      end

      def on_error(msg_id, code, response)
        collector.response_received!
        logger.error("[ERROR] Collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}); MSG ID: #{msg_id}, CODE: #{code}, RESPONSE: #{response}")
        metrics&.record_error(:receptor_error_response)
      end

      def on_timeout(msg_id)
        collector.response_received!
        logger.error("[ERROR] Timeout when collecting #{entity_type}, :source_uid => #{collector.send(:source)}, :refresh_state_uuid => #{refresh_state_uuid}; MSG ID: #{msg_id}, ")
        metrics&.record_error(:receptor_timeout)
      end

      # There can be multiple 'on_eof' calls
      # i.e. service_offerings entity type consists of 2 tower entity types (job templates/workflow templates)
      def on_eof(_msg_id)
        collector.response_received!
        async_requests_remaining.decrement

        if async_requests_remaining.value == 0
          collector.async_collecting_finished(entity_type, refresh_state_uuid, total_parts.value)

          # Sweeping is disabled for targeted_refresh and operations
          # and in case of errors
          if sweeping_enabled.value
            collector.async_sweep_inventory(entity_type, refresh_state_uuid, sweep_scope.to_a, total_parts.value, refresh_state_started_at)
          end
        end
      end

      private

      attr_writer :connection, :entity_type, :refresh_state_uuid, :refresh_state_started_at, :sweeping_enabled, :sweep_scope, :total_parts
    end
  end
end
