require "topological_inventory/ansible_tower/connection"
require "topological_inventory/ansible_tower/receptor/exception"
require "topological_inventory/ansible_tower/receptor/api_object"
require "topological_inventory/ansible_tower/receptor/template"
require "topological_inventory/ansible_tower/receptor/response_worker"
require "topological_inventory/ansible_tower/receptor/response"
require "topological_inventory/ansible_tower/receptor/tower_api"

module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiClient < TopologicalInventory::AnsibleTower::Connection
      include Logging

      RECEPTOR_REQUEST_PATH = "job".freeze

      attr_reader :tenant_account, :base_url, :username, :password,
                  :receptor_base_url, :receptor_id,
                  :verify_ssl
      attr_accessor :response_worker

      def initialize(base_url, username, password,
                     receptor_id, receptor_base_url, tenant_account, response_worker,
                     verify_ssl: ::OpenSSL::SSL::VERIFY_NONE)
        self.base_url          = base_url
        self.username          = username
        self.password          = password
        self.verify_ssl        = verify_ssl
        self.receptor_id       = receptor_id
        self.receptor_base_url = receptor_base_url
        self.response_worker   = response_worker
        self.tenant_account    = tenant_account
      end

      def api
        self
      end

      def tower_api
        @tower_api ||= TowerApi.new(api)
      end

      def receptor_endpoint_url
        return @receptor_endpoint if @receptor_endpoint.present?

        @receptor_endpoint = File.join(receptor_base_url, RECEPTOR_REQUEST_PATH)
      end

      def class_from_type(type)
        tower_api.send("#{type}_class")
      end

      def get(path)
        Receptor::ApiObject.new(api, path).get
      end

      def config
        Receptor::ApiObject.new(api, 'config')
      end

      def credentials
        Receptor::ApiObject.new(api, 'credentials')
      end

      def credential_types
        Receptor::ApiObject.new(api, 'credential_types')
      end

      def job_templates
        Receptor::Template.new(api, 'job_templates')
      end

      def workflow_job_templates
        Receptor::Template.new(api,'workflow_job_templates')
      end

      def workflow_job_template_nodes
        Receptor::ApiObject.new(api,'workflow_job_template_nodes')
      end

      def jobs
        Receptor::ApiObject.new(api,'jobs')
      end

      def workflow_jobs
        Receptor::ApiObject.new(api,'workflow_jobs')
      end

      def workflow_job_nodes
        Receptor::ApiObject.new(api,'workflow_job_nodes')
      end

      def inventories
        Receptor::ApiObject.new(api, 'inventories')
      end

      def default_api_path
        "/api/v2".freeze
      end

      protected

      attr_writer :tenant_account, :base_url, :username, :password,
                  :receptor_base_url, :receptor_id,
                  :verify_ssl
    end
  end
end
