require "topological_inventory-api-client"
require "topological_inventory/ansible_tower/operations/applied_inventories/request"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::AppliedInventories::Request do
  include AppliedInventories::Methods
  extend AppliedInventories::Data

  let(:account_number) { '123456' }
  let(:identity) { {"x-rh-identity" => Base64.strict_encode64({"identity" => {"account_number" => account_number, "user" => {"is_org_admin" => true}}}.to_json)} }
  let(:topology_api_default) { double('Topological Inv. default API') }
  let(:topology_api) { double('Topological API Client', :api => topology_api_default) }

  subject do
    operation = described_class.new({}, identity)
    allow(operation).to receive(:topology_api).and_return(topology_api)
    operation
  end

  before do
    allow_any_instance_of(TopologicalInventory::AnsibleTower::Operations::AppliedInventories::Parser).to receive(:topology_api).and_return(topology_api)
  end

  context "#applied_inventories" do
    templates_and_workflows_data.each_pair do |sample_name, workflow_definition|
      it "processing ordering '#{sample_name}'" do
        stub_api_init(workflow_definition)
        subject.params                                                = {'service_offering_id' => workflow_definition[:template].id, 'service_parameters' => {}}
        subject.params['service_parameters']['prompted_inventory_id'] = workflow_definition[:prompted_inventory].id if workflow_definition[:prompted_inventory]

        expect(subject).to receive(:update_task).with(nil,
                                                      :state  => "running",
                                                      :status => "ok")
        expect(subject).to receive(:update_task).with(nil,
                                                      :state   => "completed",
                                                      :status  => "ok",
                                                      :context => {:applied_inventories => match_array(workflow_definition[:applied_inventories].map(&:id))})
        subject.run
      end
    end
  end
end
