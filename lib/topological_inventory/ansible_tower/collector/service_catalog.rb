module TopologicalInventory::AnsibleTower
  class Collector
    module ServiceCatalog
      def get_service_credentials(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.credentials.klass.endpoint}")
          enumerator = connection.api.credentials.all(:page_size => limits[:service_credentials])
          enumerator.each do |service_credential|
            block.call(service_credential)
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_credentials' of service catalog.")
      end

      def get_service_credential_types(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.credential_types.klass.endpoint}")
          enumerator = connection.api.credential_types.all(:page_size => limits[:service_credential_types])
          enumerator.each do |service_credential_type|
            block.call(service_credential_type)
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_credential_type' of service catalog.")
      end

      def get_service_inventories(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.inventories.klass.endpoint}")
          enumerator = connection.api.inventories.all(:page_size => limits[:service_inventories])
          enumerator.each do |inventory|
            block.call(inventory)
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_inventories' of service catalog.")
      end

      def get_service_offerings(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.job_templates.klass.endpoint}")
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.workflow_job_templates.klass.endpoint}")
          {:job_template          => connection.api.job_templates.all(:page_size => limits[:service_offerings]),
           :workflow_job_template => connection.api.workflow_job_templates.all(:page_size => limits[:service_offerings])}.each_pair do |type, enumerator|
            enumerator.each do |template|
              block.call(
                :template      => template,
                :template_type => type,
                :survey_spec   => get_service_plan(template)
              )
            end
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_offerings' of service catalog.")
      end

      def get_service_offering_nodes(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.workflow_job_template_nodes.klass.endpoint}")
          enumerator = connection.api.workflow_job_template_nodes.all(:page_size => limits[:service_offering_nodes])
          enumerator.each do |service_offering_node|
            credentials = connection.api.workflow_job_template_nodes.find_all_by_url(service_offering_node.related.credentials)
            block.call(:node => service_offering_node, :credentials => credentials)
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_offering_nodes' of service catalog.")
      end

      def get_service_instances(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.jobs.klass.endpoint}")
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.workflow_jobs.klass.endpoint}")
          {:job          => connection.api.jobs.all(:page_size => limits[:service_instances]),
           :workflow_job => connection.api.workflow_jobs.all(:page_size => limits[:service_instances])}.each_pair do |type, enumerator|
            enumerator.each do |job|
              block.call(
                :job      => job,
                :job_type => type
              )
            end
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_instances' of service catalog")
      end

      def get_service_instance_nodes(connection)
        fnc = lambda do |&block|
          log_external_url("#{connection_manager.api_url(tower_hostname)}/#{connection.api.workflow_job_nodes.klass.endpoint}")
          enumerator = connection.api.workflow_job_nodes.all(:page_size => limits[:service_instance_nodes])
          enumerator.each do |service_instance_node|
            credentials = connection.api.workflow_job_nodes.find_all_by_url(service_instance_node.related.credentials)
            block.call(:node => service_instance_node, :credentials => credentials)
          end
        end
        TopologicalInventory::AnsibleTower::Iterator.new(fnc, "Couldn't fetch 'service_instance_nodes' of service catalog.")
      end

      # TODO: It seems that each request are sent twice in ansible_tower_client
      # But don't know why yet
      def get_service_plan(template)
        template.survey_spec_hash if template.survey_enabled
      end
    end
  end
end
