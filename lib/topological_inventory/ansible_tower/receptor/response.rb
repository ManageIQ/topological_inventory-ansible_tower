module TopologicalInventory::AnsibleTower
  module Receptor
    class Response
      delegate :[], :to => :hash

      def initialize(hash)
        self.hash = hash
      end

      def body
        hash['body']
      end

      private

      attr_accessor :hash
    end
  end
end
