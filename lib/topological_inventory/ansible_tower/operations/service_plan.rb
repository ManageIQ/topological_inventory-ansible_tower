require "topological_inventory-api-client"
require "topological_inventory/ansible_tower/operations/core/ansible_tower_client"
require "topological_inventory/ansible_tower/operations/core/service_order_mixin"
require "topological_inventory/ansible_tower/operations/core/topology_api_client"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class ServicePlan
        include Logging
        include Core::TopologyApiClient
        include Core::ServiceOrderMixin

        attr_accessor :params, :identity

        def initialize(params = {}, identity = nil, receptor_client = nil)
          @params   = params
          @identity = identity
        end
      end
    end
  end
end
