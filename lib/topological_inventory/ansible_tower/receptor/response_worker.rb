module TopologicalInventory::AnsibleTower
  module Receptor
    class ResponseWorker
      def self.instance
        @instance ||= self.new
      end

      def initialize
        @mutex   = Mutex.new
        @started = false
        @registered_messages = {}
      end

      def start
        @mutex.synchronize do
          return if @started
          @started = true
        end
        Thread.new { listen }
      end

      def register_msg_id(msg_id, api_object, response_method = :response_received)
        @registered_messages[msg_id] = { :api_object => api_object, :method => response_method }
      end

      private

      def listen
        # Open a connection to the messaging service
        client = ManageIQ::Messaging::Client.open(default_messaging_opts)

        logger.info("Receptor Response worker started...")
        client.subscribe_topic(queue_opts) do |message|
          process_message(message)
        end
      ensure
        client&.close
      end


      # TODO: update
      def process_message(message)
        message_id = message.message.to_s
        payload = message.payload
        if (callback = @registered_messages[message_id]).present?
          callback[:api_object].send(callback[:method], message_id, payload)
        else
          logger.warn("Received Unknown Receptor Message ID (#{message_id}): #{payload.inspect}")
        end
      end

      # TODO: update
      def queue_name
        "platform.topological-inventory.receptor-response"
      end

      def queue_opts
        {
          :max_bytes   => 50_000,
          :service     => queue_name,
          :persist_ref => "topological-inventory-receptor-response"
        }
      end

      def default_messaging_opts
        {
          :protocol   => :Kafka,
          :client_ref => "topological-inventory-receptor-response",
          :group_ref  => "topological-inventory-receptor-response"
        }
      end
    end
  end
end