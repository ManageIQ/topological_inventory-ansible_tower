module TopologicalInventory
  module AnsibleTower
    module Operations
      module Core
        module ServiceOrderMixin
          SLEEP_POLL = 10
          POLL_TIMEOUT = 1800


          def order
            task_id, service_offering_id, service_plan_id, order_params = params.values_at(
              "task_id", "service_offering_id", "service_plan_id", "order_params")

            logger.info("ServiceOffering#order: Task(id: #{task_id}), ServiceOffering(:id #{service_offering_id}): Order method entered")

            update_task(task_id, :state => "running", :status => "ok")

            service_plan          = topology_api_client.show_service_plan(service_plan_id.to_s) if service_plan_id
            service_offering_id ||= service_plan.service_offering_id
            service_offering      = topology_api_client.show_service_offering(service_offering_id.to_s)

            source_id = service_offering.source_id
            client    = ansible_tower_client(source_id, task_id, identity)

            job_type = parse_svc_offering_type(service_offering)

            logger.info("ServiceOffering#order: Task(id: #{task_id}): Ordering ServiceOffering(id: #{service_offering.id}, source_ref: #{service_offering.source_ref}): Launching Job...")
            job = client.order_service(job_type, service_offering.source_ref, order_params)
            logger.info("ServiceOffering#order: Task(id: #{task_id}): Ordering ServiceOffering(id: #{service_offering.id}, source_ref: #{service_offering.source_ref}): Job(:id #{job&.id}) has launched.")

            update_task(task_id,
                        :state             => "running",
                        :status            => client.job_status_to_task_status(job.status),
                        :source_id         => source_id.to_s,
                        :target_source_ref => job.id.to_s,
                        :target_type       => "ServiceInstance")

            logger.info("ServiceOffering#order: Task(id: #{task_id}): Ordering ServiceOffering(id: #{service_offering.id}, source_ref: #{service_offering.source_ref})...Task updated")
          rescue StandardError => err
            logger.error("ServiceOffering#order: Task(id: #{task_id}), ServiceOffering(id: #{service_offering&.id} source_ref: #{service_offering&.source_ref}): Ordering error: #{err.cause} #{err}\n#{err.backtrace.join("\n")}")
            update_task(task_id, :state => "completed", :status => "error", :context => {:error => err.to_s})
          end

          def ansible_tower_client(source_id, task_id, identity)
            Core::AnsibleTowerClient.new(source_id, task_id, identity)
          end

          # Type defined by collector here:
          # lib/topological_inventory/ansible_tower/parser/service_offering.rb:12
          def parse_svc_offering_type(service_offering)
            job_type = service_offering.extra[:type] if service_offering.extra.present?

            raise "Missing service_offering's type: #{service_offering.inspect}" if job_type.blank?
            job_type
          end
        end
      end
    end
  end
end
