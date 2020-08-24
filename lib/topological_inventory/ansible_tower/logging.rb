require "topological_inventory/providers/common/logging"

module TopologicalInventory
  module AnsibleTower
    class << self
      attr_writer :logger
    end

    def self.logger
      # Set the log level to whatever we specify in the environment if it is present, defaulting to DEBUG
      @logger ||= TopologicalInventory::Providers::Common::Logger.new.tap { |log| log.level = ENV['LOG_LEVEL'] if ENV['LOG_LEVEL'] }
    end

    module Logging
      def logger
        TopologicalInventory::AnsibleTower.logger
      end

      def log_with(request_id)
        old_request_id = Thread.current[:request_id]
        Thread.current[:request_id] = request_id

        yield
      ensure
        Thread.current[:request_id] = old_request_id
      end
    end
  end
end
