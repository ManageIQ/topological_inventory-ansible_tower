require "topological_inventory-api-client"
require "topological_inventory/ansible_tower/operations/order/request"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::Order::Request do
  context "#run" do
    let(:metrics)  { double('Metrics') }
    let(:subject)  { described_class.new(params, identity, metrics) }
    let(:identity) { {"account_number" => "12345"} }
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

    let(:ansible_tower_client) { TopologicalInventory::AnsibleTower::Operations::AnsibleTowerClient.new('1', params['task_id']) }

    let(:api) { double("API") }
    let(:topology_api_client) { double("Topological API Client", :api => api) }

    before do
      expect(subject).to receive(:topology_api).and_return(topology_api_client)
    end

    it "ordering the service offering" do
      expect(subject).to receive(:update_task).with(1, :state => "running", :status => "ok")
      expect(api).to(receive(:show_service_offering).with("1")
                       .and_return(service_offering))

      expect(subject).to receive(:ansible_tower_client)
        .with(service_offering.source_id, params["task_id"], identity)
        .and_return(ansible_tower_client)

      job = double
      allow(job).to receive(:id).and_return(42)
      allow(job).to receive(:status).and_return('successful')

      allow(ansible_tower_client).to receive(:job_external_url).and_return('https://tower.example.com/job/1')
      expect(ansible_tower_client).to receive(:order_service)
        .with(service_offering.extra[:type], service_offering.source_ref, params["order_params"])
        .and_return(job)

      expect(subject).to(receive(:update_task)
                           .with(1,
                                 :context           => {
                                   :service_instance => {
                                     :job_status => 'successful',
                                     :url        => 'https://tower.example.com/job/1'
                                   }
                                 },
                                 :state             => "running",
                                 :status            => ansible_tower_client.job_status_to_task_status(job.status),
                                 :source_id         => '1',
                                 :target_source_ref => job.id.to_s,
                                 :target_type       => 'ServiceInstance'))
      status = subject.run
      expect(status).to eq(subject.operation_status[:success])
    end

    it "ordering service_offering with exception" do
      allow(subject).to receive(:logger).and_return(double.as_null_object)

      allow(subject).to receive(:update_task)
      expect(api).to receive(:show_service_offering).and_raise(TopologicalInventoryApiClient::ApiError)

      expect(metrics).to receive(:record_error).with(:order)
      expect(subject.run).to eq(subject.operation_status[:error])
    end
  end
end
