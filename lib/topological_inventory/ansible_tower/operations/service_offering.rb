require "topological_inventory/providers/common/operations/service_offering"
require "topological_inventory/ansible_tower/operations/core/ansible_tower_client"
require "topological_inventory/ansible_tower/operations/applied_inventories/parser"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class ServiceOffering< TopologicalInventory::Providers::Common::Operations::ServiceOffering
        include Logging

        def endpoint_client(source_id, task_id, identity)
          Core::AnsibleTowerClient.new(source_id, task_id, identity)
        end

        def applied_inventories
          task_id, service_offering_id, service_params = params.values_at("task_id", "service_offering_id", "service_parameters")

          service_offering = topology_api_client.show_service_offering(service_offering_id.to_s)
          prompted_inventory_id = service_params['prompted_inventory_id']

          parser = init_parser(identity, service_offering, prompted_inventory_id)
          inventories = if parser.is_workflow_template?(service_offering)
                          parser.load_workflow_template_inventories
                        else
                          [ parser.load_job_template_inventory ].compact
                        end

          update_task(task_id, :state => "completed", :status => "ok", :context => { :applied_inventories => inventories.map(&:id) })
        rescue StandardError => err
          logger.error("[Task #{task_id}] AppliedInventories error: #{err}\n#{err.backtrace.join("\n")}")
          update_task(task_id, :state => "completed", :status => "error", :context => { :error => err.to_s })
        end

        private

        def init_parser(identity, service_offering, prompted_inventory_id)
          TopologicalInventory::AnsibleTower::Operations::AppliedInventories::Parser.new(identity, service_offering, prompted_inventory_id)
        end
      end
    end
  end
end
