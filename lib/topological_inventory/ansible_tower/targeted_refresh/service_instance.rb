require "topological_inventory/ansible_tower/collector"
require "topological_inventory/providers/common/operations/source"
require "topological_inventory/providers/common/mixins/sources_api"
require "topological_inventory/providers/common/mixins/x_rh_headers"
require "topological_inventory/ansible_tower/receptor/async_receiver"
require 'concurrent'
require 'time'

module TopologicalInventory
  module AnsibleTower
    module TargetedRefresh
      class ServiceInstance < TopologicalInventory::AnsibleTower::Collector
        include TopologicalInventory::Providers::Common::Mixins::SourcesApi
        include TopologicalInventory::Providers::Common::Mixins::XRhHeaders

        REFS_PER_REQUEST_LIMIT = 20

        def initialize(payload = {})
          self.operation = 'ServiceInstance'
          self.params    = payload['params']
          self.source_id = payload['source_id']

          self.identity = params.to_a.first.to_h['request_context']
          # TODO: add metrics exporter
          super(payload['source_uid'], nil)
        end

        # Entrypoint for 'ServiceInstance.refresh' operation
        def refresh
          self.operation = "#{operation}#refresh"

          return if params_missing?

          # Connection settings
          set_connection_data!
          logger.info_ext(operation, "Connection set successfully")

          # Get all tasks
          tasks, @refresh_state_uuid = {}, SecureRandom.uuid
          @parts_requested_cnt, @parts_received_cnt = Concurrent::AtomicFixnum.new(0), Concurrent::AtomicFixnum.new(0)
          @source_refs_requested, @source_refs_received = [], Concurrent::Array.new

          params.to_a.each do |task|
            if task['task_id'].blank? || task['source_ref'].blank?
              logger.warn_ext(operation, "Missing data for task: #{task}")
              next
            end
            tasks[task['task_id']] = task['source_ref']

            if tasks.length == REFS_PER_REQUEST_LIMIT
              refresh_part(tasks)
              tasks = {}
            end
          end

          refresh_part(tasks) unless tasks.empty?

          archive_not_received_service_instances unless on_premise?
        rescue => err
          logger.error_ext(operation, "Error: #{err.message}\n#{err.backtrace.join("\n")}")
        end

        def async_save_inventory(refresh_state_uuid, parser)
          refresh_state_part_collected_at = Time.now.utc
          refresh_state_part_uuid = SecureRandom.uuid
          save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid, refresh_state_part_collected_at)

          remember_received_service_instances(parser)
        end

        def async_collecting_finished(entity_type, refresh_state_uuid, total_parts)
          logger.info_ext(operation, "Finished collecting of #{entity_type} (#{refresh_state_uuid}). Total parts: #{total_parts}")
          @parts_received_cnt.increment

          archive_not_received_service_instances if @parts_requested_cnt == @parts_received_cnt.value
        end

        private

        attr_accessor :identity, :operation, :params, :source_id

        def required_params
          %w[source_id source params]
        end

        def params_missing?
          is_missing = false
          required_params.each do |attr|
            if (is_missing = send(attr).blank?)
              logger.error_ext(operation, "Missing #{attr} for the availability_check request [Source ID: #{source_id}]")
              break
            end
          end

          is_missing
        end

        def refresh_part(tasks)
          tasks_id = tasks.keys.join(' | id: ')

          # API request, nodes and jobs under workflow job not needed
          query_params = {
            :id__in    => tasks.values.join(','),
            :page_size => limits['service_instances']
          }

          @parts_requested_cnt.increment
          @source_refs_requested += tasks.values

          if on_premise?
            refresh_part_on_premise(tasks_id, query_params)
          else
            refresh_part_cloud(tasks_id, query_params)
          end
        end

        def refresh_part_on_premise(_tasks_id, query_params)
          refresh_state_started_at = Time.now.utc
          receptor_params = {:accept_encoding => 'gzip', :fetch_all_pages => true}

          receiver = TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver.new(self, connection,
                                                                                     'service_instances',
                                                                                     @refresh_state_uuid,
                                                                                     refresh_state_started_at,
                                                                                     :sweeping_enabled => false)
          get_service_instances(connection, query_params,
                                :on_premise        => true,
                                :receptor_receiver => receiver,
                                :receptor_params   => receptor_params)
        end

        def refresh_part_cloud(tasks_id, query_params)
          parser = TopologicalInventory::AnsibleTower::Parser.new(:tower_url => tower_hostname)

          get_service_instances(connection, query_params).each do |service_instance|
            parser.parse_service_instance(service_instance)
          end

          # Sending to Ingress API
          logger.info_ext(operation, "Task[ id: #{tasks_id} ] Sending to Ingress API...")
          save_inventory(parser.collections.values, inventory_name, schema_name, @refresh_state_uuid, SecureRandom.uuid)

          remember_received_service_instances(parser)

          logger.info_ext(operation, "Task[ id: #{tasks_id} ] Sending to Ingress API...Complete")
        end

        def connection
          @connection ||= begin
            tower_user     = authentication.username unless on_premise?
            tower_passwd   = authentication.password unless on_premise?
            account_number = account_number_by_identity(identity)

            connection_manager.connect(
              :base_url       => full_hostname(endpoint),
              :username       => tower_user,
              :password       => tower_passwd,
              :receptor_node  => endpoint.receptor_node.to_s.strip,
              :account_number => account_number
            )
          end
        end

        def set_connection_data!
          raise TopologicalInventory::Providers::Common::Operations::Source::ERROR_MESSAGES[:endpoint_not_found] unless endpoint

          unless on_premise?
            raise TopologicalInventory::Providers::Common::Operations::Source::ERROR_MESSAGES[:authentication_not_found] unless authentication
          end

          self.tower_hostname = full_hostname(endpoint)
        end

        def remember_received_service_instances(parser)
          @source_refs_received += parser.collections[:service_instances]&.data&.map(&:source_ref).to_a
        end

        # source_refs not received were deleted in Tower => has to be archived
        def archive_not_received_service_instances
          not_received = @source_refs_requested - @source_refs_received
          if not_received.present?
            archived_at = Time.now.utc.iso8601
            collection = TopologicalInventoryIngressApiClient::InventoryCollectionServiceInstance.new(:name => :service_instances, :data => [])

            not_received.each do |source_ref|
              svc_instance = TopologicalInventoryIngressApiClient::ServiceInstance.new(:archived_at => archived_at,
                                                                                       :extra       => {:status => 'deleted', :task_status => 'error'},
                                                                                       :source_ref  => source_ref)
              collection.data << svc_instance
            end
            logger.info_ext(operation, "Archiving (source_refs: #{not_received.join(',')}). Jobs were deleted...")
            save_inventory([collection], inventory_name, schema_name, @refresh_state_uuid, SecureRandom.uuid)
            logger.info_ext(operation, "Archiving (source_refs: #{not_received.join(',')}). Complete")
          end
        end

        def default_refresh_type
          'targeted-refresh'
        end
      end
    end
  end
end
