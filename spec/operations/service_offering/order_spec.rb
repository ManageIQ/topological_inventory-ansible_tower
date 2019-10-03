require "topological_inventory-api-client"
require "topological_inventory/ansible_tower/operations/service_offering"
RSpec.describe TopologicalInventory::AnsibleTower::Operations::ServiceOffering do
  context "#order" do
    let(:subject)  { described_class.new(params, identity) }
    let(:identity) { {"account_number" => "12345" } }
    let(:service_offering) do
      TopologicalInventoryApiClient::ServiceOffering.new(
        :id => "1", :source_id => "1", :source_ref => "2", :name => "My Job Template", :extra => {:type => "job_template"}
      )
    end
    let(:params) do
      {
        "order_params"        => {
          "service_offering_id"         => 1,
          "service_parameters"          => {
            :name   => "Job 1",
            :param1 => "Test Topology",
            :param2 => 50
          },
          "provider_control_parameters" => {}
        },
        "service_offering_id" => 1,
        "task_id"             => 1 # in tp-inv api (Task)
      }
    end

    it "orders the service plan" do
      topology_api_client = double
      expect(topology_api_client).to receive(:show_service_offering).with("1")
        .and_return(service_offering)
      expect(subject).to receive(:topology_api_client).and_return(topology_api_client)

      ansible_tower_client = double
      expect(ansible_tower_client).to receive(:order_service)
        .with(service_offering, nil, params["order_params"])
      expect(subject).to receive(:endpoint_client)
        .with(service_offering.source_id, params["task_id"], identity)
        .and_return(ansible_tower_client)

      expect(subject).to receive(:poll_order_complete_thread)
      subject.order
    end
  end
end
