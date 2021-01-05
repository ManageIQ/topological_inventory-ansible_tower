require "topological_inventory/ansible_tower/operations/order/request"
require "topological_inventory/ansible_tower/operations/applied_inventories/request"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class ServiceOffering
        attr_accessor :metrics, :params, :identity

        def initialize(params = {}, identity = nil, metrics = nil)
          @params   = params
          @identity = identity
          @metrics  = metrics
        end

        def order
          Order::Request.new(params, identity, metrics).run
        end

        def applied_inventories
          AppliedInventories::Request.new(params, identity, metrics).run
        end
      end
    end
  end
end
