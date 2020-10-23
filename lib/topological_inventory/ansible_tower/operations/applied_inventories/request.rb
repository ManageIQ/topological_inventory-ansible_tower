require "topological_inventory-api-client"
require "topological_inventory/providers/common/mixins/topology_api"
require "topological_inventory/ansible_tower/operations/applied_inventories/parser"

module TopologicalInventory
  module AnsibleTower
    module Operations
      module AppliedInventories
        class Request
          include Logging
          include TopologicalInventory::Providers::Common::Mixins::TopologyApi

          attr_accessor :params, :identity

          def initialize(params, identity)
            self.params   = params
            self.identity = identity
          end

          def run
            task_id, service_offering_id, service_params = params.values_at("task_id", "service_offering_id", "service_parameters")
            service_params                             ||= {}

            update_task(task_id, :state => "running", :status => "ok")

            service_offering      = topology_api.api.show_service_offering(service_offering_id.to_s)
            prompted_inventory_id = service_params['prompted_inventory_id']

            parser      = init_parser(identity, service_offering, prompted_inventory_id)
            inventories = if parser.is_workflow_template?(service_offering)
                            parser.load_workflow_template_inventories
                          else
                            [parser.load_job_template_inventory].compact
                          end

            update_task(task_id, :state => "completed", :status => "ok", :context => {:applied_inventories => inventories.map(&:id)})
          rescue StandardError => err
            logger.error("[Task #{task_id}] AppliedInventories error: #{err}\n#{err.backtrace.join("\n")}")
            update_task(task_id, :state => "completed", :status => "error", :context => {:error => err.to_s})
          end

          private

          def init_parser(identity, service_offering, prompted_inventory_id)
            TopologicalInventory::AnsibleTower::Operations::AppliedInventories::Parser.new(identity, service_offering, prompted_inventory_id)
          end
        end
      end
    end
  end
end
