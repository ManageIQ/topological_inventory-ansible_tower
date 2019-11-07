require "topological_inventory-api-client"
require "topological_inventory/providers/common/operations/topology_api_client"
require "topological_inventory/ansible_tower/operations/applied_inventories/tree_item"
module TopologicalInventory
  module AnsibleTower
    module Operations
      module AppliedInventories
        #
        # Terminology:
        #
        # * Workflow Template                      = ServiceOffering with extra[:type] == 'workflow_job_template'
        # * Job Template                           = ServiceOffering with extra[:type] == 'job_template'
        # * Workflow Job Template Node (or "Node") = ServiceOfferingNode
        # * Inventory                              = ServiceInventory
        #
        class Parser
          include Logging
          include TopologicalInventory::Providers::Common::Operations::TopologyApiClient

          attr_accessor :identity

          def initialize(identity, root_wf_template, prompted_inventory_id = nil)
            self.identity = identity
            self.root_tree_item = TreeItem.new(root_wf_template)

            self.prompted_inventory = load_inventory(prompted_inventory_id) if prompted_inventory_id

            self.template_inventories = {} # { template => { inventory_id:, inventory:} }
            self.node_inventories     = {} # { node => { inventory_id:, inventory: } }
          end

          # Entrypoint for standalone JobTemplate
          #
          # @param tree_item [TopologicalInventory::AnsibleTower::Operations::AppliedInventories::TreeItem] tree node with Job Template
          # @return [TopologicalInventoryApiClient::ServiceInventory, nil]
          def load_job_template_inventory(tree_item = root_tree_item)
            job_template = tree_item.item
            if job_template.service_inventory_id
              template_inventories[job_template] = { :inventory_id => job_template.service_inventory_id}
              load_inventories
            end

            get_inventory(tree_item)
          end

          # Entrypoint for Workflow Template
          #
          # @param tree_item [TopologicalInventory::AnsibleTower::Operations::AppliedInventories::TreeItem] tree node with Workflow Template
          # @return [Array<TopologicalInventoryApiClient::ServiceInventory>]
          def load_workflow_template_inventories(tree_item = root_tree_item)
            load_nodes_and_templates(tree_item)
            template_inventories[tree_item.item] = { :inventory_id => tree_item.item.service_inventory_id } if tree_item.item.service_inventory_id
            load_inventories

            compute_used_inventories(tree_item)
          end

          def is_job_template?(template)
            TreeItem.is_job_template?(template)
          end

          def is_workflow_template?(template)
            TreeItem.is_workflow_template?(template)
          end

          private

          attr_accessor :node_inventories, :prompted_inventory, :root_tree_item,
                        :template_child_nodes, :template_inventories

          # Loads nodes, templates and IDs of all inventories
          # @param wf_template_tree_item [TopologicalInventory::AnsibleTower::Operations::AppliedInventories::TreeItem] tree item with Workflow Template
          def load_nodes_and_templates(wf_template_tree_item)
            load_child_nodes(wf_template_tree_item)
            load_templates_for_nodes(wf_template_tree_item)
          end

          # @param parent_wf_template_tree_item [TopologicalInventory::AnsibleTower::Operations::AppliedInventories::TreeItem] tree item with Workflow Template
          def load_child_nodes(parent_wf_template_tree_item)
            root_wf_template = parent_wf_template_tree_item.item
            topology_api_client.list_service_offering_nodes(:filter => { :root_service_offering_id => root_wf_template.id }).data.each do |node|

              node_tree_item = TreeItem.new(node)
              TreeItem.connect(:child  => node_tree_item,
                               :parent => parent_wf_template_tree_item)

              # Set node inventory key for latter one-query load
              node_inventories[node] = { :inventory_id => node.service_inventory_id } if node.service_inventory_id
            end
          end

          def load_templates_for_nodes(parent_wf_template_tree_item)
            child_templates_ids = parent_wf_template_tree_item.children.collect { |tree_item| tree_item.item&.service_offering_id }.compact.uniq

            topology_api_client.list_service_offerings(:filter => { :id => { :eq => child_templates_ids }}).data.each do |template|
              template_tree_item = TreeItem.new(template)

              parent_wf_template_tree_item.children.each do |node_tree_item|
                if template.id == node_tree_item.item.service_offering_id
                  TreeItem.connect(:child  => template_tree_item,
                                   :parent => node_tree_item)
                  break
                end
              end

              if template_tree_item.parent.nil?
                raise "Workflow Node for Template not found! [Template: #{template.id}]"
              end

              # Set template inventory key for latter one-query load
              template_inventories[template] = { :inventory_id => template.service_inventory_id } if template.service_inventory_id
              #
              # Load tree for each child template which is workflow template
              #
              if is_workflow_template?(template)
                load_nodes_and_templates(template_tree_item) # recursive call
              end
            end
          end

          def load_inventories
            load_node_inventories
            load_template_inventories
          end

          # Loads inventories for nodes
          def load_node_inventories
            if (nodes = node_inventories.keys).present?
              node_inventory_ids = nodes.map(&:service_inventory_id).compact.uniq
              topology_api_client.list_service_inventories(:filter => { :id => { :eq => node_inventory_ids }}).data.each do |inventory|
                node_inventories.each_pair do |node, hash|
                  if node.service_inventory_id == inventory.id
                    hash[:inventory] = inventory
                    break
                  end
                end
              end
            end
          end

          # Loads inventories for templates
          def load_template_inventories
            if (templates = template_inventories.keys).present?
              template_inventory_ids = templates.map(&:service_inventory_id).compact.uniq
              topology_api_client.list_service_inventories(:filter => { :id => { :eq => template_inventory_ids }}).data.each do |inventory|
                template_inventories.each_pair do |template, hash|
                  if template.service_inventory_id == inventory.id
                    hash[:inventory] = inventory
                    break
                  end
                end
              end
            end
          end

          # Computes used inventory for each Job Template in root Workflow template
          # *Recursive* method
          def compute_used_inventories(template_tree_item)
            template_tree_item.children.collect do |child_node_tree_item|
              child_template_tree_item = child_node_tree_item.children.first
              raise "Template for Node not loaded! [Node: #{child_node_tree_item.item.id}]" if child_template_tree_item.nil?

              if child_template_tree_item.job_template?
                get_inventory(child_template_tree_item)
              elsif child_template_tree_item.workflow_template?
                compute_used_inventories(child_template_tree_item) # recursive call
              end
            end.compact.flatten.uniq
          end

          #
          # Computes inventory for given Job/Workflow template
          # *Recursive* method
          #
          def get_inventory(template_tree_item)
            template = template_tree_item.item

            if prompt_on_launch?(template)
              # node is nil if template is standalone JobTemplate or root WorkflowTemplate
              if (node_tree_item = template_tree_item.parent).nil?
                prompted_inventory || inventory_for(template)
              else
                node                    = node_tree_item.item
                root_template_tree_item = node_tree_item.parent
                root_template           = root_template_tree_item.item

                root_inventory = if prompt_on_launch?(root_template) && !loop_detected?(template, root_template)
                                   get_inventory(root_template_tree_item) # recursive call
                                 else
                                   inventory_for(root_template)
                                 end
                root_inventory || inventory_for(node) || inventory_for(template)
              end
            else
              inventory_for(template)
            end
          end

          # @param template [] Workflow Template or Job Template
          def prompt_on_launch?(template)
            template.extra[:ask_inventory_on_launch]
          end

          # workflow loop detection, TODO not working for 2+level cycles
          def loop_detected?(template, root_template)
            template.id == root_template.id
          end

          def load_inventory(inventory_id)
            topology_api_client.show_service_inventory(inventory_id)
          end

          def inventory_for(node_or_template)
            if node_or_template.kind_of?(TopologicalInventoryApiClient::ServiceOfferingNode)
              node_inventories[node_or_template][:inventory] if node_inventories[node_or_template].present?
            else
              template_inventories[node_or_template][:inventory] if template_inventories[node_or_template].present?
            end
          end
        end
      end
    end
  end
end