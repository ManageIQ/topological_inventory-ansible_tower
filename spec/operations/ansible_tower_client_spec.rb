require "topological_inventory/ansible_tower/operations/core/ansible_tower_client"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::Core::AnsibleTowerClient do
  let(:order_params) do
    {
      'service_plan_id'             => 1,
      'service_parameters'          => {:name   => "Job 1",
                                        :param1 => "Test Topology",
                                        :param2 => 50},
      'provider_control_parameters' => {}
    }
  end

  let(:source_id) { 1 }
  let(:identity) { {'x-rh-identity' => '1234567890'} }
  let(:task_id) { 10 }
  let(:ansible_tower_client) { described_class.new(source_id, task_id, identity) }

  before do
    ansible_tower, @api = double, double
    allow(ansible_tower_client).to receive(:ansible_tower).and_return(ansible_tower)
    allow(ansible_tower).to receive(:api).and_return(@api)

    allow(ansible_tower_client).to receive(:logger).and_return(double('null_object').as_null_object)
  end

  describe "#order_service" do
    let(:job_templates) { double }
    let(:job_template) { double }
    let(:job) { double }
    let(:service_offering) { double("service offering") }

    before do
      allow(service_offering).to receive(:source_ref).and_return(1)
      allow(job_templates).to receive(:find).and_return(job_template)
      allow(job_template).to receive(:launch).and_return(job)
    end

    it "launches job_template and returns job" do
      allow(service_offering).to receive(:extra).and_return({:type => 'job_template'})
      allow(@api).to receive(:job_templates).and_return(job_templates)

      expect(@api).to receive(:job_templates).once
      expect(job_template).to receive(:launch).with(:extra_vars => order_params['service_parameters'])

      svc_instance = ansible_tower_client.order_service(service_offering, nil, order_params)
      expect(svc_instance).to eq(job)
    end

    it "launches workflow and returns workflow job" do
      allow(service_offering).to receive(:extra).and_return({:type => 'workflow_job_template'})
      allow(@api).to receive(:workflow_job_templates).and_return(job_templates)

      expect(@api).to receive(:workflow_job_templates).once
      expect(job_template).to receive(:launch).with(:extra_vars => order_params['service_parameters'])

      svc_instance = ansible_tower_client.order_service(service_offering, nil, order_params)
      expect(svc_instance).to eq(job)
    end

    it "raises error when service_offering doesn't have type" do
      expect(service_offering).to receive(:extra).and_return(nil)

      expect { ansible_tower_client.order_service(service_offering, nil, order_params) }.to raise_error("Missing service_offering's type: #{service_offering.inspect}")
    end
  end

  describe "#wait_for_provision_complete" do
    before do
      @jobs, @job = double, double
      allow(@api).to receive(:jobs).and_return(@jobs)
      allow(@jobs).to receive(:find).and_return(@job)
      allow(@job).to receive(:id).and_return(123)
      allow(@job).to receive(:type).and_return("job")

      stub_const("#{described_class}::POLL_TIMEOUT", 0.5)
      stub_const("#{described_class}::SLEEP_POLL", 0.1)
    end

    it "calls api until job finished" do
      allow(@job).to receive(:status).and_return(nil)

      allow(@job).to receive(:finished).and_return(true)
      expect(@jobs).to receive(:find).once

      expect(@api).to receive(:jobs).exactly(1).times
      expect(@api).to receive(:workflow_jobs).exactly(0).times

      job = ansible_tower_client.wait_for_provision_complete(task_id, @job, {})
      expect(job.id).to eq(123)
    end

    it "calls api and searches for workflow_jobs" do
      allow(@api).to receive(:workflow_jobs).and_return(@jobs)
      allow(@job).to receive(:status).and_return(nil)

      allow(@job).to receive(:type).and_return("workflow_job")

      allow(@job).to receive(:finished).and_return(true)
      expect(@jobs).to receive(:find).once

      expect(@api).to receive(:jobs).exactly(0).times
      expect(@api).to receive(:workflow_jobs).exactly(1).times

      job = ansible_tower_client.wait_for_provision_complete(task_id, @job, {})
      expect(job.id).to eq(123)
    end

    it "calls api until timeout (when job not finished)" do
      allow(@job).to receive(:status).and_return(nil)

      allow(@job).to receive(:finished).and_return(nil)
      expect(@jobs).to receive(:find).exactly((described_class::POLL_TIMEOUT / described_class::SLEEP_POLL).to_i).times

      ansible_tower_client.wait_for_provision_complete(task_id, @job, {})
    end

    it "updates task with job status" do
      @status = 0
      allow(@job).to receive(:status) { @status += 1 }

      allow(@job).to receive(:finished).and_return(nil)

      allow(ansible_tower_client).to receive(:update_task)
      expect(ansible_tower_client).to receive(:update_task)
        .exactly((described_class::POLL_TIMEOUT / described_class::SLEEP_POLL).to_i).times

      ansible_tower_client.wait_for_provision_complete(task_id, @job, {})
    end
  end
end
