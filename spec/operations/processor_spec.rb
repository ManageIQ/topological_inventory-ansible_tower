require "topological_inventory/ansible_tower/operations/processor"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::Processor do
  let(:message) { double("ManageIQ::Messaging::ReceivedMessage", :message => operation_name, :payload => payload) }
  let(:operation_name) { 'Testing.operation' }
  let(:params) { {'source_id' => 1, 'external_tenant' => '12345', 'task_id' => task_id} }
  let(:payload) { {"params" => params, "request_context" => double('request_context')} }
  let(:task_id) { '42' }

  subject { described_class.new(message, nil) }

  describe "#process" do
    context "ServiceOffering" do
      let(:svc_offering_class) { TopologicalInventory::AnsibleTower::Operations::ServiceOffering }
      let(:service_offering) { svc_offering_class.new(params) }
      let(:operation) { double('Operation object') }

      before do
        allow(svc_offering_class).to receive(:new).and_return(service_offering)
      end

      context "ordering task" do
        let(:operation_name) { 'ServiceOffering.order' }

        it "orders service offering" do
          expect(service_offering).to receive(:order).and_call_original

          expect(TopologicalInventory::AnsibleTower::Operations::Order::Request).to receive(:new).and_return(operation)
          expect(operation).to receive(:run)

          subject.process
        end
      end

      context "applied_inventories task" do
        let(:operation_name) { 'ServiceOffering.applied_inventories' }

        it "runs applied inventories" do
          expect(service_offering).to receive(:applied_inventories).and_call_original

          expect(TopologicalInventory::AnsibleTower::Operations::AppliedInventories::Request).to receive(:new).and_return(operation)
          expect(operation).to receive(:run)

          subject.process
        end
      end
    end

    context "Source.availability_check task" do
      let(:source_class) { TopologicalInventory::AnsibleTower::Operations::Source }
      let(:operation_name) { 'Source.availability_check' }

      it "runs availability check" do
        source = source_class.new(params)
        allow(source_class).to receive(:new).and_return(source)

        expect(source).to receive(:availability_check)

        subject.process
      end
    end
  end
end
