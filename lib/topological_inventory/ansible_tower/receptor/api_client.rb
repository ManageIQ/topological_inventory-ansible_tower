require "topological_inventory/ansible_tower/connection"
require "topological_inventory/ansible_tower/receptor/exception"
require "topological_inventory/ansible_tower/receptor/api_object"
require "topological_inventory/ansible_tower/receptor/template"
require "topological_inventory/ansible_tower/receptor/response"
require "topological_inventory/ansible_tower/receptor/tower_api"

module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiClient < TopologicalInventory::AnsibleTower::Connection
      include Logging

      RECEPTOR_REQUEST_PATH = "job".freeze

      attr_reader :account_number, :base_url, :username, :password,
                  :receptor_client, :receptor_node,
                  :verify_ssl

      def initialize(base_url, username, password, receptor_client,
                     receptor_node, account_number,
                     verify_ssl: ::OpenSSL::SSL::VERIFY_NONE)
        self.base_url          = api_url(base_url)
        self.username          = username
        self.password          = password
        self.verify_ssl        = verify_ssl
        self.receptor_client   = receptor_client

        self.receptor_node     = receptor_node
        self.account_number    = account_number
        receptor_client.identity_header = identity_header
      end

      def api
        self
      end

      def tower_api
        @tower_api ||= TowerApi.new(api)
      end

      def receptor_endpoint_url
        return @receptor_endpoint if @receptor_endpoint.present?

        @receptor_endpoint = receptor_client.config.job_url
      end

      def class_from_type(type)
        tower_api.send("#{type}_class")
      end

      def get(path)
        Receptor::ApiObject.new(api, path).get
      end

      def post(path, post_data)
        Receptor::ApiObject.new(api, path).post(post_data)
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

      # TODO: test it with surveys collecting
      def api_url(base_url)
        base_url = "https://#{base_url}" unless base_url =~ %r{\Ahttps?:\/\/} # HACK: URI can't properly parse a URL with no scheme
        uri      = URI(base_url)
        uri.path = default_api_path if uri.path.blank?
        uri.to_s
      end

      def default_api_path
        "/api/v2".freeze
      end

      # org_id with any number is required by receptor_client controller
      def identity_header(account = account_number)
        @identity ||= {
          "x-rh-identity" => Base64.strict_encode64(
            {"identity" => {"account_number" => account, "user" => { "is_org_admin" => true }, "internal" => {"org_id" => '000001'}}}.to_json
          )
        }
      end

      protected

      attr_writer :account_number, :base_url, :username, :password,
                  :receptor_client, :receptor_node,
                  :verify_ssl
    end
  end
end
