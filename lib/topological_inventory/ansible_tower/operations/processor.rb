require "topological_inventory/ansible_tower/logging"
require "topological_inventory-api-client"
require "topological_inventory/ansible_tower/operations/core/topology_api_client"
require "topological_inventory/ansible_tower/operations/service_offering"
require "topological_inventory/ansible_tower/operations/service_plan"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class Processor
        include Logging
        include Core::TopologyApiClient

        def self.process!(message, receptor_client)
          model, method = message.message.to_s.split(".")
          new(model, method, message.payload, receptor_client).process
        end

        # @param payload [Hash] https://github.com/ManageIQ/topological_inventory-api/blob/master/app/controllers/api/v0/service_plans_controller.rb#L32-L41
        def initialize(model, method, payload, receptor_client)
          self.model    = model
          self.method   = method
          self.params   = payload["params"]
          self.identity = payload["request_context"]
          self.receptor_client = receptor_client
        end

        def process
          logger.info(status_log_msg)

          impl = "#{Operations}::#{model}".safe_constantize&.new(params, identity, receptor_client)
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

        attr_accessor :identity, :model, :method, :params, :receptor_client

        def status_log_msg(status = nil)
          "Processing #{model}##{method} [#{params}]...#{status}"
        end
      end
    end
  end
end
