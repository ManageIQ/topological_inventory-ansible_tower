require "manageiq-messaging"
require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/operations/processor"
require "topological_inventory/ansible_tower/operations/source"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Worker
        include Logging

        def initialize(messaging_client_opts = {})
          self.messaging_client_opts = default_messaging_opts.merge(messaging_client_opts)
        end

        def run
          # Open a connection to the messaging service
          client = ManageIQ::Messaging::Client.open(messaging_client_opts)

          logger.info("Topological Inventory AnsibleTower Operations worker started...")
          client.subscribe_topic(queue_opts) do |message|
            logger.info("Received message #{message.message}, #{message.payload}")
            process_message(message)
          end
        rescue => err
          logger.error("#{err}\n#{err.backtrace.join("\n")}")
        ensure
          client&.close
        end

        private

        attr_accessor :messaging_client_opts

        def process_message(message)
          Processor.process!(message)
        rescue StandardError => err
          logger.error("#{err}\n#{err.backtrace.join("\n")}")
          raise
        ensure
          message.ack
        end

        def queue_name
          "platform.topological-inventory.operations-ansible-tower"
        end

        def queue_opts
          {
            :auto_ack    => false,
            :max_bytes   => 50_000,
            :service     => queue_name,
            :persist_ref => "topological-inventory-operations-ansible-tower"
          }
        end

        def default_messaging_opts
          {
            :protocol   => :Kafka,
            :client_ref => "topological-inventory-operations-ansible-tower",
            :group_ref  => "topological-inventory-operations-ansible-tower"
          }
        end
      end
    end
  end
end
