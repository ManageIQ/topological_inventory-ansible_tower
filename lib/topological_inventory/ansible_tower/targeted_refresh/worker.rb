require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/connection_manager"
require "topological_inventory/ansible_tower/targeted_refresh/processor"
require "topological_inventory/ansible_tower/messaging_client"

module TopologicalInventory
  module AnsibleTower
    module TargetedRefresh
      # TODO: example of payload
      class Worker
        include Logging

        def run
          TopologicalInventory::AnsibleTower::ConnectionManager.start_receptor_client

          # Open a connection to the messaging service
          begin
            logger.info("Topological Inventory AnsibleTower Refresh worker started...")
            client.subscribe_topic(queue_opts) do |message|
              process_message(message)
            end
          rescue Rdkafka::RdkafkaError => err
            logger.error("#{err.class.name}\n#{err.message}\n#{err.backtrace.join("\n")}")
            client(:renew => true)
            retry
          end
        rescue => err
          logger.error("#{err.class.name}\n#{err.message}\n#{err.backtrace.join("\n")}")
        ensure
          client&.close
          TopologicalInventory::AnsibleTower::ConnectionManager.stop_receptor_client
        end

        private

        def client(renew: false)
          @client = nil if renew

          @client ||= TopologicalInventory::AnsibleTower::MessagingClient.default.targeted_refresh_listener(:renew => renew)
        end

        def queue_opts
          TopologicalInventory::AnsibleTower::MessagingClient.default.targeted_refresh_listener_queue_opts
        end

        def process_message(message)
          model, method = message.message.to_s.split(".")
          payload = JSON.parse(message.payload) if message.payload.present?

          logger.info("Received message #{model}##{method}, #{payload}")
          TargetedRefresh::Processor.process!(message, payload)
        rescue JSON::ParserError
          logger.error("#{model}##{method} - Failed to parse payload: #{message.payload}")
          raise
        rescue => err
          tasks_id = if payload
                       ids = payload['params'].to_a.collect { |task| task['task_id'] }
                       ids.compact!
                     end
          logger.error("#{model}##{method} - Task[ id: #{tasks_id.to_a.join(' | id: ')} ] #{err.class.name}\n#{err.message}\n#{err}\n#{err.backtrace.join("\n")}")
          raise
        ensure
          message.ack
        end
      end
    end
  end
end
