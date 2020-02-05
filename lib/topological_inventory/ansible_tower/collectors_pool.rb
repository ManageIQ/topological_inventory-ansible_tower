require "topological_inventory/providers/common/collectors_pool"
require "topological_inventory/ansible_tower/collector"
require "topological_inventory/ansible_tower/logging"

module TopologicalInventory::AnsibleTower
  class CollectorsPool < TopologicalInventory::Providers::Common::CollectorsPool
    include Logging

    def initialize(config_name, metrics, queue_host: nil, queue_port: nil)
      super(config_name, metrics)
      self.queue_host = queue_host
      self.queue_port = queue_port
    end

    def path_to_config
      File.expand_path("../../../config", File.dirname(__FILE__))
    end

    def path_to_secrets
      File.expand_path("../../../secret", File.dirname(__FILE__))
    end

    def source_valid?(source, secret)
      missing_data = [source.source,
                      source.host,
                      secret["username"],
                      secret["password"]].select do |data|
        data.to_s.strip.blank?
      end
      missing_data.empty?
    end

    def new_collector(source, secret)
      url = URI::Generic.build(:scheme => source.scheme.to_s.strip.presence || 'https',
                               :host   => source.host.to_s.strip,
                               :port   => source.port.to_s.strip)
      TopologicalInventory::AnsibleTower::Collector.new(source.source,
                                                        url.to_s,
                                                        secret["username"],
                                                        secret["password"],
                                                        metrics,
                                                        :standalone_mode => false,
                                                        :queue_host      => queue_host,
                                                        :queue_port      => queue_port)
    end

    private

    attr_accessor :queue_host, :queue_port
  end
end
