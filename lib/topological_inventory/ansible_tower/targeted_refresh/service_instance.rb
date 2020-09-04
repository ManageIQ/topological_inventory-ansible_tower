require "topological_inventory/ansible_tower/collector"
require "topological_inventory/providers/common/operations/source"
require "topological_inventory/providers/common/operations/sources_api_client"
require "topological_inventory/ansible_tower/receptor/async_receiver"

module TopologicalInventory
  module AnsibleTower
    module TargetedRefresh
      class ServiceInstance < TopologicalInventory::AnsibleTower::Collector
        REFS_PER_REQUEST_LIMIT = 20

        def initialize(payload = {})
          self.params    = payload['params']
          self.source_id = payload['source_id']

          # TODO: add metrics exporter
          super(payload['source_uid'], nil)
        end

        # Entrypoint for 'ServiceInstance.refresh' operation
        def refresh
          return if params_missing?

          # Connection settings
          set_connection_data!
          logger.info("ServiceInstance#refresh - Connection set successfully")

          # Get all tasks
          tasks, refresh_state_uuid = {}, SecureRandom.uuid
          params.to_a.each do |task|
            if task['task_id'].blank? || task['source_ref'].blank?
              logger.warn("ServiceInstance#refresh - missing data for task: #{task}")
              next
            end
            tasks[task['task_id']] = task['source_ref']

            if tasks.length == REFS_PER_REQUEST_LIMIT
              refresh_part(tasks, refresh_state_uuid, SecureRandom.uuid)
              tasks = {}
            end
          end

          refresh_part(tasks, refresh_state_uuid, SecureRandom.uuid) unless tasks.empty?
        rescue => err
          logger.error("ServiceInstance#refresh - Error: #{err.message}\n#{err.backtrace.join("\n")}")
        end

        def async_save_inventory(refresh_state_uuid, parser)
          refresh_state_part_collected_at = Time.now.utc
          refresh_state_part_uuid = SecureRandom.uuid
          save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid, refresh_state_part_collected_at)
        end

        def async_collecting_finished(entity_type, refresh_state_uuid, total_parts)
          logger.info("ServiceInstance#refresh: finished collecting of #{entity_type} (#{refresh_state_uuid}). Total parts: #{total_parts}")
        end

        private

        attr_accessor :params, :source_id

        def required_params
          %w[source_id source params]
        end

        def params_missing?
          is_missing = false
          required_params.each do |attr|
            if (is_missing = send(attr).blank?)
              logger.error("ServiceInstance#refresh - Missing #{attr} for the availability_check request [Source ID: #{source_id}]")
              break
            end
          end

          is_missing
        end

        def refresh_part(tasks, refresh_state_uuid, refresh_state_part_uuid)
          tasks_id = tasks.keys.join(' | id: ')

          # API request, nodes and jobs under workflow job not needed
          query_params = {
            :id__in    => tasks.values.join(','),
            :page_size => limits['service_instances']
          }

          if on_premise?
            refresh_part_on_premise(tasks_id, refresh_state_uuid, query_params)
          else
            refresh_part_cloud(tasks_id, refresh_state_uuid, refresh_state_part_uuid, query_params)
          end
        end

        def refresh_part_on_premise(_tasks_id, refresh_state_uuid, query_params)
          refresh_state_started_at = Time.now.utc
          receptor_params = {:accept_encoding => 'gzip', :fetch_all_pages => true}

          receiver = TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver.new(self, connection,
                                                                                     'service_instances',
                                                                                     refresh_state_uuid,
                                                                                     refresh_state_started_at,
                                                                                     :sweeping_enabled => false)
          get_service_instances(connection, query_params,
                                :on_premise        => true,
                                :receptor_receiver => receiver,
                                :receptor_params   => receptor_params)
        end

        def refresh_part_cloud(tasks_id, refresh_state_uuid, refresh_state_part_uuid, query_params)
          parser = TopologicalInventory::AnsibleTower::Parser.new(:tower_url => tower_hostname)

          get_service_instances(connection, query_params).each do |service_instance|
            parser.parse_service_instance(service_instance)
          end

          # Sending to Ingress API
          logger.info("ServiceInstance#refresh - Task[ id: #{tasks_id} ] Sending to Ingress API...")
          save_inventory(parser.collections.values, inventory_name, schema_name, refresh_state_uuid, refresh_state_part_uuid)
          logger.info("ServiceInstance#refresh - Task[ id: #{tasks_id} ] Sending to Ingress API...Complete")
        end

        def connection
          @connection ||= begin
                            tower_user = authentication.username unless on_premise?
                            tower_passwd = authentication.password unless on_premise?

                            connection_manager.connect(
                              :base_url       => tower_hostname,
                              :username       => tower_user,
                              :password       => tower_passwd,
                              :receptor_node  => endpoint.receptor_node.to_s.strip,
                              :account_number => account_number
                            )
                          end
        end

        def on_premise?
          @on_premise ||= endpoint.receptor_node.to_s.strip.present?
        end

        def set_connection_data!
          raise TopologicalInventory::Providers::Common::Operations::Source::ERROR_MESSAGES[:endpoint_not_found] unless endpoint

          unless on_premise?
            raise TopologicalInventory::Providers::Common::Operations::Source::ERROR_MESSAGES[:authentication_not_found] unless authentication
          end

          self.tower_hostname = full_hostname(endpoint)
        end

        # TODO: Join with other operations
        def endpoint
          @endpoint ||= api_client.fetch_default_endpoint(source_id)
        rescue => e
          logger.error("ServiceInstance#refresh - Failed to fetch Endpoint for Source #{source_id}: #{e.message}")
          nil
        end

        def authentication
          @authentication ||= api_client.fetch_authentication(source_id, endpoint)
        rescue => e
          logger.error("ServiceInstance#refresh - Failed to fetch Authentication for Source #{source_id}: #{e.message}")
          nil
        end

        # Queries Sources API in the context of first task
        def identity
          @identity ||= params.to_a.first['request_context']
        end

        def api_client
          @api_client ||= TopologicalInventory::Providers::Common::Operations::SourcesApiClient.new(identity)
        end

        # TODO: Join with PR #112 (ordering)
        def account_number
          return unless on_premise?
          return @account_number if @account_number
          return if identity.try(:[], 'x-rh-identity').nil?

          identity_hash = JSON.parse(Base64.decode64(identity['x-rh-identity']))
          @account_number = identity_hash.dig('identity', 'account_number')
        rescue JSON::ParserError => e
          logger.error("ServiceInstance#refresh - Failed to parse identity header: #{e.message}")
          nil
        end

        def full_hostname(endpoint)
          if on_premise?
            "receptor://#{endpoint.receptor_node}"
          else
            endpoint.host.tap { |host| host << ":#{endpoint.port}" if endpoint.port }
          end
        end

        def default_refresh_type
          'targeted-refresh'
        end
      end
    end
  end
end
