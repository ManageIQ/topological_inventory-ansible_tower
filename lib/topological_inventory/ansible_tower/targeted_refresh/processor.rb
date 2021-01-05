require "topological_inventory/ansible_tower/logging"
require "topological_inventory/providers/common/mixins/topology_api"
require "topological_inventory/ansible_tower/targeted_refresh/service_instance"

module TopologicalInventory
  module AnsibleTower
    module TargetedRefresh
      class Processor
        include Logging
        include TopologicalInventory::Providers::Common::Mixins::TopologyApi

        # Messages older than threshold are skipped
        SENT_AT_THRESHOLD = 300

        def self.process!(message, payload)
          model, method = message.message.to_s.split(".")
          new(model, method, payload).process
        end

        def initialize(model, method, payload)
          self.model = model
          self.method = method
          self.payload = payload
          self.sent_at_threshold = (ENV['SENT_AT_THRESHOLD'] || SENT_AT_THRESHOLD).to_i.seconds
        end

        def process
          return if skip_old_payload?

          logger.info(status_log_msg)
          impl = "#{TargetedRefresh}::#{model}".safe_constantize&.new(payload)
          if impl&.respond_to?(method)
            result = impl&.send(method)

            logger.info(status_log_msg("Complete"))
            result
          else
            logger.warn(status_log_msg("Not Implemented!"))

            update_tasks
          end
        end

        private

        attr_accessor :identity, :model, :method, :payload, :sent_at_threshold

        def skip_old_payload?
          sent_at = Time.parse(payload['sent_at']).utc
          sent_at < sent_at_threshold.ago.utc
        rescue
          true # Skip incompatible payloads
        end

        def update_tasks
          with_params do
            payload['params'].each do |item|
              next if item['task_id'].blank?

              update_task(item['task_id'].to_s,
                          :state   => "completed",
                          :status  => "error",
                          :context => {:error => "#{model}##{method} not implemented"})
            end
          end
        end

        def status_log_msg(status = nil)
          log_task_text = with_params do
            tasks_id = payload['params'].collect { |task| task['task_id'] }.compact
            tasks_id.present? ? "Task[ id: #{tasks_id.to_a.join(' | id: ')} ]: " : ''
          end

          "Processing #{model}##{method} - #{log_task_text}#{status}"
        end

        def with_params
          yield if payload.present? && payload['params'].kind_of?(Array)
        end
      end
    end
  end
end
