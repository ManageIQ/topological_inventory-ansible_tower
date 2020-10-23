require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/connection_manager"
require "topological_inventory/providers/common/mixins/sources_api"
require "topological_inventory/providers/common/mixins/x_rh_headers"

module TopologicalInventory
  module AnsibleTower
    module Operations
      class AnsibleTowerClient
        include Logging
        include ::TopologicalInventory::Providers::Common::Mixins::SourcesApi
        include ::TopologicalInventory::Providers::Common::Mixins::XRhHeaders

        attr_accessor :connection_manager, :operation

        def initialize(source_id, task_id, identity = nil)
          self.identity  = identity
          self.operation = 'ServiceOffering#order'
          self.source_id = source_id
          self.task_id   = task_id

          self.connection_manager = TopologicalInventory::AnsibleTower::ConnectionManager.new(source_id)
        end

        # Format of order params (Input for Catalog - created by Collector, Output is produced by catalog - input of this worker)
        #
        # @example:
        #
        # * Input (ServicePlan.create_json_schema field)(created by lib/topological_inventory/ansible_tower/parser/service_plan.rb)
        #     {"schema":
        #       {"fields":[
        #         {"name":"providerControlParameters", ... },
        #         {"name":"NAMESPACE", "type":"text", ...},
        #         {"name":"MEMORY_LIMIT","type":"text","default":"512Mi","isRequired":true,...},
        #         {"name":"POSTGRESQL_USER",type":"text",...},
        #         ...
        #        ]
        #       },
        #      "defaultValues":{"NAMESPACE":"openshift","MEMORY_LIMIT":"512Mi","POSTGRESQL_USER":"","VOLUME_CAPACITY":"...}
        #     }
        #
        # * Output (== @param **order_params**):
        #
        #     { "NAMESPACE":"openshift",
        #       "MEMORY_LIMIT":"512Mi",
        #       "POSTGRESQL_USER":"",
        #       "providerControlParameters":{"namespace":"default"},
        #       ...
        #     }"
        def order_service(job_type, job_template_id, order_params)
          job_template = if job_type == 'workflow_job_template'
                           connection.api.workflow_job_templates.find(job_template_id)
                         else
                           connection.api.job_templates.find(job_template_id)
                         end

          job = job_template.launch(job_values(order_params))

          # This means that api_client:job_template.launch() called job.find(nil), which returns list of jobs
          # => status error was returned, but api_client doesn't return errors
          raise ::AnsibleTowerClient::ResourceNotFoundError, "Job not found" if job.respond_to?(:count)

          job
        end

        def self.job_status_to_task_status(job_status)
          case job_status
          when 'error', 'failed' then
            'error'
          else
            'ok'
          end
        end

        def job_status_to_task_status(job_status)
          self.class.job_status_to_task_status(job_status)
        end

        # Ansible Tower's URL to Job/Workflow
        def self.job_external_url(job, tower_base_url)
          path = job.type == 'workflow_job' ? 'workflows' : 'jobs/playbook'
          File.join(tower_url(tower_base_url), "/#/#{path}", job.id.to_s)
        end

        def job_external_url(job)
          tower_host = [endpoint.scheme, endpoint.host].join('://')
          self.class.job_external_url(job, tower_host)
        end

        def self.tower_url(hostname)
          if hostname.to_s.index('http').nil?
            File.join('https://', hostname)
          else
            hostname
          end
        end

        private

        attr_accessor :identity, :task_id, :source_id

        def job_values(order_parameters)
          if order_parameters["service_parameters"].blank?
            {}
          else
            {:extra_vars => order_parameters["service_parameters"]}
          end
        end

        def connection
          @connection ||= begin
                            tower_user     = authentication.username unless on_premise?
                            tower_passwd   = authentication.password unless on_premise?
                            account_number = account_number_by_identity(identity) unless on_premise?

                            connection_manager.connect(
                              :base_url       => full_hostname(endpoint),
                              :username       => tower_user,
                              :password       => tower_passwd,
                              :receptor_node  => endpoint.receptor_node.to_s.strip,
                              :account_number => account_number
                            )
                          end
        end
      end
    end
  end
end
