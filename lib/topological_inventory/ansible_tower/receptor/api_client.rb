require "topological_inventory/ansible_tower/connection"
require "topological_inventory/ansible_tower/receptor/api_object"
require "topological_inventory/ansible_tower/receptor/template"
require "topological_inventory/ansible_tower/receptor/response_worker"

module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiClient < TopologicalInventory::AnsibleTower::Connection
      include Logging

      attr_accessor :response_worker

      def initialize(base_url, username, password,
                     receptor_id, receptor_base_url, response_worker,
                     verify_ssl: ::OpenSSL::SSL::VERIFY_NONE)
        self.base_url                 = base_url
        self.username                 = username
        self.password                 = password
        self.verify_ssl               = verify_ssl
        self.receptor_id              = receptor_id
        self.receptor_base_url        = receptor_base_url
        self.response_worker = response_worker
      end

      def api
        self
      end

      def receptor_endpoint_url
        return @receptor_endpoint if @receptor_endpoint.present?

        @receptor_endpoint = File.join(receptor_base_url, 'job')
      end

      def start
        Receptor::ResponseWorker.instance.start
      end

      def job_templates
        Receptor::Template.new(api_client, 'job_templates')
      end

      def workflow_job_templates
        Receptor::Template.new(api_client,'workflow_job_templates')
      end

      def workflow_job_template_nodes
        Receptor::ApiObject.new(api_client,'workflow_job_template_nodes')
      end

      def jobs
        Receptor::ApiObject.new(api_client,'jobs')
      end

      def workflow_jobs
        Receptor::ApiObject.new(api_client,'workflow_jobs')
      end

      def workflow_job_nodes
        Receptor::ApiObject.new(api_client,'workflow_job_nodes')
      end

      protected

      attr_accessor :base_url, :username, :password,
                    :receptor_base_url, :receptor_id,
                    :verify_ssl
    end
  end
end
