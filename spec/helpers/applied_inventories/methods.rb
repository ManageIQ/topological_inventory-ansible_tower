module AppliedInventories
  module Methods
    include AppliedInventories::Data

    def stub_api_init(workflow)
      # call in ordering
      expect(topology_api_default).to receive(:show_service_offering)
                                       .with(workflow[:template].id.to_s)
                                       .and_return(workflow[:template])
      # call in parser#initialize
      if workflow[:prompted_inventory].present?
        expect(topology_api_default).to receive(:show_service_inventory)
                                         .with(workflow[:prompted_inventory].id.to_s)
                                         .and_return(workflow[:prompted_inventory])
      end

      template_inventories, node_inventories = [], []
      if is_job_template?(workflow[:template])
        template_inventories << workflow[:inventory] unless workflow[:inventory].nil?
      elsif is_workflow_template?(workflow[:template])
        # calls in parser#load_nodes_and_templates
        stub_api_init_template(workflow, template_inventories, node_inventories)
      end

      # calls in parser#load_node_inventories
      node_inventories.compact!
      if node_inventories.present?
        expect(topology_api_default).to receive(:list_service_inventories)
                                         .with(hash_including(:filter => {:id => {:eq => match_array(node_inventories.map(&:id))}}))
                                         .and_return(inventory_collection(node_inventories))
      end
      # calls in parser#load_template_inventories
      template_inventories.compact!
      if template_inventories.present?
        expect(topology_api_default).to(receive(:list_service_inventories)
                                         .with(:filter => {:id => {:eq => match_array(template_inventories.map(&:id).uniq)}})
                                         .and_return(inventory_collection(template_inventories)))
      end
    end

    def stub_api_init_template(parent_template, template_inventories, node_inventories)
      template_inventories << parent_template[:inventory] if parent_template[:inventory]


      return if is_job_template?(parent_template[:template])

      child_nodes = if parent_template[:child_nodes].nil?
                      []
                    else
                      parent_template[:child_nodes].collect {|node_hash| node_hash[:node] }
                    end
      expect(topology_api_default).to receive(:list_service_offering_nodes)
                                       .with(:filter => {:root_service_offering_id => parent_template[:template].id})
                                       .and_return(node_collection(child_nodes))

      return if child_nodes.blank?

      template_ids, templates, templates_hash = [], [], []
      parent_template[:child_nodes].each do |child_node|
        node_inventories << child_node[:inventory]
        next if child_node[:template].blank?

        templates << child_node[:template][:template]
        templates_hash << child_node[:template]
        template_ids << child_node[:template][:template].id
      end
      expect(topology_api_default).to(receive(:list_service_offerings)
                                       .with(:filter => {:id => {:eq => match_array(template_ids.uniq)}})
                                       .and_return(template_collection(templates)))

      templates_hash.each do |template_hash|
        stub_api_init_template(template_hash, template_inventories, node_inventories)
      end
    end

    def is_job_template?(template)
      template.extra[:type] == 'job_template'
    end

    def is_workflow_template?(template)
      template.extra[:type] == 'workflow_job_template'
    end
  end
end
