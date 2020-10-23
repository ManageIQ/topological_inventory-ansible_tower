require "topological_inventory/ansible_tower/operations/ansible_tower_client"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::AnsibleTowerClient do
  let(:order_params) do
    {
      'service_plan_id'             => 1,
      'service_parameters'          => {:name   => "Job 1",
                                        :param1 => "Test Topology",
                                        :param2 => 50},
      'provider_control_parameters' => {}
    }
  end

  let(:identity) { {'x-rh-identity' => Base64.encode64({'identity' => {'account_number' => '123456'}}.to_json)} }
  let(:logger) { double('null_object').as_null_object }
  let(:receptor_client) { ::ReceptorController::Client.new(:logger => logger) }
  let(:source_id) { 1 }
  let(:task_id) { 10 }

  subject { described_class.new(source_id, task_id, identity) }

  before do
    allow(receptor_client).to receive_messages(:start => nil, :stop => nil)
    allow(::ReceptorController::Client).to receive(:new).and_return(receptor_client)

    allow(subject).to receive(:logger).and_return(logger)
  end

  describe "#ansible_tower" do
    let(:authentication) { nil }

    before do
      allow(subject).to receive(:endpoint).and_return(default_endpoint)
      allow(subject).to receive(:authentication).and_return(authentication)
    end

    context "on-premise" do
      let(:receptor_node_id) { 'receptor-node' }
      let(:default_endpoint) { SourcesApiClient::Endpoint.new(:receptor_node => receptor_node_id, :source_id => source_id.to_s) }

      it "connects through receptor connection" do
        expect(subject.send(:connection)).to be_kind_of(TopologicalInventory::AnsibleTower::Receptor::Connection)
      end
    end

    context "cloud" do
      let(:default_endpoint) { SourcesApiClient::Endpoint.new(:scheme => 'https', :host => 'tower.example.com', :port => nil, :source_id => source_id.to_s) }
      let(:authentication) { SourcesApiClient::Authentication.new(:username => 'redhat', :password => 'redhat') }

      it "connects through ansible-tower-client connection" do
        expect(subject.send(:connection)).to be_kind_of(::AnsibleTowerClient::Connection)
      end
    end
  end

  describe "#order_service_plan" do
    let(:job_templates) { double }
    let(:job_template) { double }
    let(:job) { double }

    before do
      ansible_tower, @api = double, double
      allow(subject).to receive(:connection).and_return(ansible_tower)
      allow(ansible_tower).to receive(:api).and_return(@api)

      allow(job_templates).to receive(:find).and_return(job_template)
      allow(job_template).to receive(:launch).and_return(job)
      expect(job_template).to receive(:launch).with(:extra_vars => order_params['service_parameters'])
    end

    it "launches job_template and returns job" do
      allow(@api).to receive(:job_templates).and_return(job_templates)

      expect(@api).to receive(:job_templates).once

      svc_instance = subject.order_service("job_template", 1, order_params)
      expect(svc_instance).to eq(job)
    end

    it "launches workflow and returns workflow job" do
      allow(@api).to receive(:workflow_job_templates).and_return(job_templates)

      expect(@api).to receive(:workflow_job_templates).once

      svc_instance = subject.order_service("workflow_job_template", 1, order_params)
      expect(svc_instance).to eq(job)
    end
  end
end
