require "topological_inventory/ansible_tower/operations/order/request"
require "topological_inventory/ansible_tower/operations/applied_inventories/request"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class ServiceOffering
        attr_accessor :params, :identity

        def initialize(params = {}, identity = nil)
          @params   = params
          @identity = identity
        end

        def order
          Order::Request.new(params, identity).run
        end

        def applied_inventories
          AppliedInventories::Request.new(params, identity).run
        end
      end
    end
  end
end
