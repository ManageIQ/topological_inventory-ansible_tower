require "topological_inventory/ansible_tower/logging"
require "topological_inventory/providers/common/mixins/topology_api"
require "topological_inventory/ansible_tower/operations/service_offering"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Processor
        include Logging
        include TopologicalInventory::Providers::Common::Mixins::TopologyApi

        def self.process!(message)
          model, method = message.message.to_s.split(".")
          new(model, method, message.payload).process
        end

        # @param payload [Hash] https://github.com/ManageIQ/topological_inventory-api/blob/master/app/controllers/api/v0/service_plans_controller.rb#L32-L41
        def initialize(model, method, payload)
          self.model    = model
          self.method   = method
          self.params   = payload["params"]
          self.identity = payload["request_context"]
        end

        def process
          logger.info(status_log_msg)
          impl = "#{Operations}::#{model}".safe_constantize&.new(params, identity)
          if impl&.respond_to?(method)
            result = impl&.send(method)

            logger.info(status_log_msg("Complete"))
            result
          else
            logger.warn(status_log_msg("Not Implemented!"))
            if params['task_id']
              update_task(params['task_id'],
                          :state   => "completed",
                          :status  => "error",
                          :context => {:error => "#{model}##{method} not implemented"})
            end
          end
        end

        private

        attr_accessor :identity, :model, :method, :params

        def status_log_msg(status = nil)
          log_task_text = "Task(id: #{params['task_id']}): " if params['task_id']

          "#{log_task_text}Processing #{model}##{method} [#{params}]...#{status}"
        end
      end
    end
  end
end
