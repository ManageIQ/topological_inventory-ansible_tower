require 'ansible_tower_client'

module TopologicalInventory::AnsibleTower
  module Receptor
    class TowerApi < ::AnsibleTowerClient::Api
      attr_accessor :receptor_api

      delegate :get, :to => :receptor_api

      def initialize(receptor_api)
        super(nil)
        self.receptor_api = receptor_api
      end

      def config
        JSON.parse(get('config').body)
      end
    end
  end
end
