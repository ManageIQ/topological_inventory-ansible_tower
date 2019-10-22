require "topological_inventory/ansible_tower/logging"
require "topological_inventory/ansible_tower/connection"
require "topological_inventory/providers/common/operations/endpoint_client/service_order"

module TopologicalInventory
  module AnsibleTower
    module Operations
      module Core
        class AnsibleTowerClient < TopologicalInventory::Providers::Common::Operations::EndpointClient::ServiceOrder
          include Logging

          attr_accessor :connection_manager

          SLEEP_POLL = 10
          POLL_TIMEOUT = 1800

          def initialize(source_id, task_id, identity = nil)
            super(source_id, task_id, identity)

            self.connection_manager = TopologicalInventory::AnsibleTower::Connection.new
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
          def order_service(service_offering, _service_plan, order_params)
            job_template = if job_type(service_offering) == 'workflow_job_template'
                             ansible_tower.api.workflow_job_templates.find(service_offering.source_ref)
                           else
                             ansible_tower.api.job_templates.find(service_offering.source_ref)
                           end

            job = job_template.launch(job_values(order_params))

            # This means that api_client:job_template.launch() called job.find(nil), which returns list of jobs
            # => status error was returned, but api_client doesn't return errors
            raise ::AnsibleTowerClient::ResourceNotFoundError, "Job not found" if job.respond_to?(:count)

            job
          end

          def wait_for_provision_complete(task_id, job, context)
            count = 0
            timeout_count = POLL_TIMEOUT / SLEEP_POLL
            loop do
              job = if job.type == 'workflow_job'
                      ansible_tower.api.workflow_jobs.find(job.id)
                    else
                      ansible_tower.api.jobs.find(job.id)
                    end

              if context[:remote_status] != job.status
                context[:remote_status] = job.status
                update_task(task_id, :state => "running", :status => task_status_for(job), :context => context)
              end

              return job if job.finished.present?

              break if (count += 1) >= timeout_count

              sleep(SLEEP_POLL) # seconds
            end
            job
          end

          def source_ref_of(job)
            job.id
          end

          def provisioned_successfully?(job)
            job.status == "successful"
          end

          def task_status_for(job)
            case job.status
            when 'error', 'failed' then 'error'
            else 'ok'
            end
          end

          private

          attr_accessor :identity, :task_id, :source_id

          # Type defined by collector here:
          # lib/topological_inventory/ansible_tower/parser/service_offering.rb:12
          def job_type(service_offering)
            job_type = service_offering.extra[:type] if service_offering.extra.present?

            raise "Missing service_offering's type: #{service_offering.inspect}" if job_type.blank?
            job_type
          end

          def job_values(order_parameters)
            if order_parameters["service_parameters"].blank?
              {}
            else
              { :extra_vars => order_parameters["service_parameters"] }
            end
          end

          def ansible_tower
            @ansible_tower ||= connection_manager.connect(
              default_endpoint.host, authentication.username, authentication.password, :verify_ssl => verify_ssl_mode
            )
          end
        end
      end
    end
  end
end
