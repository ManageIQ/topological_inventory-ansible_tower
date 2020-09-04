module TopologicalInventory::AnsibleTower
  class Collector
    module ServiceCatalog
      def get_service_credentials(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[credentials]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params)
      end

      def get_service_credential_types(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[credential_types]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params)
      end

      def get_service_inventories(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[inventories]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params)
      end

      def get_service_offerings(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[job_templates workflow_job_templates]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params) do
          # transformation of [Workflow] Job Template to parser-compatible hash
          # + subqueries for service_plans (surveys)
          lambda do |template|
            {
              :template      => template,
              :template_type => template.type.to_sym,
              :survey_spec   => get_service_plan(template)
            }
          end
        end
      end

      def get_service_offering_nodes(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[workflow_job_template_nodes]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params) do
          # transformation of Workflow Job Template Node to parser-compatible hash
          # + subqueries for node's credentials
          lambda do |service_offering_node|
            api_obj     = connection.api.workflow_job_template_nodes
            credentials = api_obj.find_all_by_url(service_offering_node.related.credentials)
            {
              :node        => service_offering_node,
              :credentials => credentials
            }
          end
        end
      end

      def get_service_instances(connection, query_params, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[jobs workflow_jobs]
        get_tower_objects(connection, query_params, tower_types, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params) do
          # transformation of Job/Workflow Job to parser-compatible hash
          lambda do |job_or_workflow|
            {
              :job  => job_or_workflow,
              :type => job_or_workflow.type.to_sym
            }
          end
        end
      end

      def get_service_instance_nodes(connection, query_params, workflow: nil, on_premise: false, receptor_receiver: nil, receptor_params: {})
        tower_types = %i[workflow_job_nodes]
        get_tower_objects(connection, query_params, tower_types, :slug => workflow&.related&.workflow_nodes, :on_premise => on_premise, :receptor_receiver => receptor_receiver, :receptor_params => receptor_params) do
          # transformation of Workflow Job Node to parser-compatible hash
          # + subqueries for node's credentials
          lambda do |service_instance_node|
            api_obj     = connection.api.workflow_job_nodes
            credentials = api_obj.find_all_by_url(service_instance_node.related.credentials)
            {
              :node        => service_instance_node,
              :credentials => credentials
            }
          end
        end
      end

      def get_service_plan(template)
        template.survey_spec_hash if template.survey_enabled
      end

      private

      # @param connection [AnsibleTowerClient::Connection | TopologicalInventory::AnsibleTower::Receptor::ApiClient]
      # @param query_params [Hash] API query params
      # @param tower_types [Array<Symbol>] i.e. %i[job_templates workflow_job_templates]
      # @param slug [String] optional, slug for calling "find_all_by_url" instead of "all"
      # @param on_premise [Boolean] Ansible Tower placement (in public/on premise)
      # @param receptor_receiver [TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver] Receiver for receptor's asynchronous responses
      # @param receptor_params [Hash] Params for Receptor node's Catalog HTTP plugin (@see https://github.com/mkanoor/receptor-catalog/README.md)
      def get_tower_objects(connection, query_params, tower_types, slug: nil, on_premise: false, receptor_receiver: nil, receptor_params: {})
        api_calls_block = lambda do |&block|
          #
          # Initializing API Calls
          api_objects = init_api_objects(connection, on_premise, query_params, receptor_params, receptor_receiver, tower_types, slug)
          #
          # Getting custom lambda block for transformation of API object to Parser compatible object
          parsing_transformation = yield if block_given?

          if on_premise
            # on-premise tower requests are asynchronous => processed in receptor_receiver
            receptor_receiver.transformation = parsing_transformation if receptor_receiver && parsing_transformation
          else
            api_objects.each do |enumerator|
              # public tower requests are synchronous => processed there (block from Collector.collector_thread)
              enumerator.each do |template|
                block.call(parsing_transformation&.call(template) || template)
              end
            end
          end
        end
        #
        # Invoking requests
        # Public Tower requests wrapped in iterator (support for .each)
        if on_premise
          receptor_receiver.async_requests_remaining.value = tower_types.size if receptor_receiver.respond_to?(:async_requests_remaining)
          api_calls_block.call
        else
          TopologicalInventory::AnsibleTower::Iterator.new(api_calls_block, "Couldn't fetch '#{tower_types.join(', ')}' of service catalog.")
        end
      end

      def init_api_objects(connection, on_premise, query_params, receptor_params, receptor_receiver, tower_types, slug = nil)
        tower_types.collect do |entity_type|
          #
          # Creating Ansible/Receptor API client objects
          api_obj = on_premise ? connection.api.send(entity_type, receptor_receiver) : connection.api.send(entity_type)
          #
          # Logging Tower Full path
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{slug || api_obj.klass.endpoint}")
          #
          # Calling Tower API
          if slug
            if on_premise
              api_obj.find_all_by_url(slug, query_params, receptor_params)
            else
              api_obj.find_all_by_url(slug, query_params)
            end
          else
            if on_premise
              api_obj.all(query_params, receptor_params)
            else
              api_obj.all(query_params)
            end
          end
        end
      end
    end
  end
end
