module TopologicalInventory::AnsibleTower
  module Receptor
    class Error         < StandardError; end
    class ClientError   < Error; end
    class ReceptorConnectionError < Error; end

    class ReceptorKafkaResponseError < Error; end
    class ReceptorNodeError < ReceptorKafkaResponseError; end
    class ReceptorUnknownResponseError < ReceptorKafkaResponseError; end


  end
end
