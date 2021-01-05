require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/operations/processor"
require "topological_inventory/ansible_tower/connection_manager"
require "topological_inventory/ansible_tower/messaging_client"
require "topological_inventory/providers/common/mixins/statuses"
require "topological_inventory/providers/common/operations/health_check"
require "topological_inventory/providers/common/operations/async_worker"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Worker
        include Logging
        include TopologicalInventory::Providers::Common::Mixins::Statuses

        ASYNC_MESSAGES = %w[Source.availability_check].freeze

        def initialize(metrics)
          self.metrics = metrics
        end

        def run
          start_workers
          logger.info("Topological Inventory AnsibleTower Operations worker started...")

          client.subscribe_topic(queue_opts) do |message|
            log_with(message.payload&.fetch_path('request_context', 'x-rh-insights-request-id')) do
              if ASYNC_MESSAGES.include?(message.message)
                logger.debug("Queuing #{message.message} message for asynchronous processing...")
                async_worker.enqueue(message)
              else
                model, method = message.message.to_s.split(".")
                logger.info("Received message #{model}##{method}, #{message.payload}")

                process_message(message)
              end
            end
          end
        rescue => err
          logger.error("#{err.cause}\n#{err.backtrace.join("\n")}")
        ensure
          client&.close
          async_worker&.stop
          TopologicalInventory::AnsibleTower::ConnectionManager.stop_receptor_client
        end

        private

        attr_accessor :metrics

        def client
          @client ||= TopologicalInventory::AnsibleTower::MessagingClient.default.worker_listener
        end

        def queue_opts
          TopologicalInventory::AnsibleTower::MessagingClient.default.worker_listener_queue_opts
        end

        def async_worker
          @async_worker ||= TopologicalInventory::Providers::Common::Operations::AsyncWorker.new(Processor, :metrics => metrics)
        end

        def process_message(message)
          result = Processor.process!(message, metrics)
          metrics&.record_operation(message.message, :status => result)
        rescue StandardError => err
          model, method = message.message.to_s.split(".")
          task_id = message.payload&.fetch_path('params', 'task_id')

          logger.error("#{model}##{method}: Task(id: #{task_id}) #{err.cause}\n#{err}\n#{err.backtrace.join("\n")}")
          metrics&.record_operation(message.message, :status => operation_status[:error])
        ensure
          message.ack
          TopologicalInventory::Providers::Common::Operations::HealthCheck.touch_file
        end

        def start_workers
          TopologicalInventory::AnsibleTower::ConnectionManager.start_receptor_client
          async_worker.start
        end
      end
    end
  end
end
