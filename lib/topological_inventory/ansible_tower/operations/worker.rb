require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/operations/processor"
require "topological_inventory/ansible_tower/operations/source"
require "topological_inventory/ansible_tower/connection_manager"
require "topological_inventory/ansible_tower/messaging_client"
require "topological_inventory/providers/common/operations/health_check"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Worker
        include Logging

        def run
          TopologicalInventory::AnsibleTower::ConnectionManager.start_receptor_client
          # Open a connection to the messaging service
          heartbeat_thread(client)

          logger.info("Topological Inventory AnsibleTower Operations worker started...")
          client.subscribe_topic(queue_opts) do |message|
            log_with(message.payload&.fetch_path('request_context', 'x-rh-insights-request-id')) do
              model, method = message.message.to_s.split(".")
              logger.info("Received message #{model}##{method}, #{message.payload}")
              process_message(message)
            end
          end
        rescue => err
          logger.error("#{err.cause}\n#{err.backtrace.join("\n")}")
        ensure
          heartbeat_thread.exit
          client&.close
          TopologicalInventory::AnsibleTower::ConnectionManager.stop_receptor_client
        end

        private

        def client
          @client ||= TopologicalInventory::AnsibleTower::MessagingClient.default.worker_listener
        end

        def queue_opts
          TopologicalInventory::AnsibleTower::MessagingClient.default.worker_listener_queue_opts
        end

        def process_message(message)
          Processor.process!(message)
        rescue StandardError => err
          model, method = message.message.to_s.split(".")
          task_id = message.payload&.fetch_path('params','task_id')
          logger.error("#{model}##{method}: Task(id: #{task_id}) #{err.cause}\n#{err}\n#{err.backtrace.join("\n")}")
          raise
        ensure
          message.ack
          TopologicalInventory::Providers::Common::Operations::HealthCheck.touch_file
        end

        # TODO: Probably move this to common eventually, if we need it elsewhere.
        def heartbeat_thread(client = nil)
          @heartbeat_thread ||= Thread.new do
            loop do
              sleep(15)
              client.send(:topic_consumer, queue_opts[:persist_ref], nil).trigger_heartbeat!
            rescue StandardError => e
              logger.error("Exception in kafka heartbeat thread: #{e.message}, restarting...")
            end
          end
        end
      end
    end
  end
end
