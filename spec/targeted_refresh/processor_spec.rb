require 'topological_inventory/ansible_tower/targeted_refresh/processor'

RSpec.describe TopologicalInventory::AnsibleTower::TargetedRefresh::Processor do
  let(:metrics) { double("Metrics") }

  describe "#self.process!" do
    let(:message) { double(:message => 'SomeModel.some_method') }
    let(:payload) { double("Payload") }

    it "expects message in Model.Method format" do
      processor = double(:process => nil)

      expect(described_class).to receive(:new)
        .with('SomeModel', 'some_method', payload, metrics)
        .and_return(processor)

      described_class.process!(message, payload, metrics)
    end
  end

  describe "#process" do
    context "on implemented operation" do
      let(:job_refs) { %w[10 20] }
      let(:message) do
        double(:message => 'ServiceInstance.refresh',
               :payload => {
                 'source_id'  => '1',
                 'source_uid' => '3bfb8667-2b00-480b-bcbf-452bfb34a440',
                 'sent_at'    => Time.now.utc.iso8601,
                 'params'     => [{:task_id => '1', :source_ref => job_refs[0], :request_context => {"x-rh-identity" => "xxx", "x-rh-insights-request-id" => "111"}},
                                  {:task_id => '2', :source_ref => job_refs[1], :request_context => {"x-rh-identity" => "yyy", "x-rh-insights-request-id" => "222"}}]
               })
      end

      subject { described_class.new('ServiceInstance', 'refresh', message.payload, metrics) }

      it "call the operation" do
        operation = double(:refresh => nil)
        expect(TopologicalInventory::AnsibleTower::TargetedRefresh::ServiceInstance).to receive(:new)
          .with(message.payload, metrics)
          .and_return(operation)

        expect(operation).to receive(:refresh)

        subject.process
      end
    end

    context "on operation without valid timestamp" do
      let(:job_refs) { %w[10 20] }

      subject { described_class.new('ServiceInstance', 'refresh', message.payload, nil) }

      context "without timestamp" do
        let(:message) do
          double(:message => 'ServiceInstance.refresh',
                 :payload => {
                   'source_id'  => '1',
                   'source_uid' => '3bfb8667-2b00-480b-bcbf-452bfb34a440',
                   'params'     => [{:task_id => '1', :source_ref => job_refs[0], :request_context => {"x-rh-identity" => "xxx", "x-rh-insights-request-id" => "111"}},
                                    {:task_id => '2', :source_ref => job_refs[1], :request_context => {"x-rh-identity" => "yyy", "x-rh-insights-request-id" => "222"}}]
                 })
        end


        it "doesn't call the operation" do
          expect(subject.send(:skip_old_payload?)).to be_truthy

          expect(TopologicalInventory::AnsibleTower::TargetedRefresh::ServiceInstance).not_to receive(:new)

          subject.process
        end
      end

      context "with old timestamp" do
        let(:message) do
          double(:message => 'ServiceInstance.refresh',
                 :payload => {
                   'source_id'  => '1',
                   'source_uid' => '3bfb8667-2b00-480b-bcbf-452bfb34a440',
                   'sent_at'    => 1.year.ago.utc.iso8601,
                   'params'     => [{:task_id => '1', :source_ref => job_refs[0], :request_context => {"x-rh-identity" => "xxx", "x-rh-insights-request-id" => "111"}},
                                    {:task_id => '2', :source_ref => job_refs[1], :request_context => {"x-rh-identity" => "yyy", "x-rh-insights-request-id" => "222"}}]
                 })
        end


        it "doesn't call the operation" do
          expect(subject.send(:skip_old_payload?)).to be_truthy

          expect(TopologicalInventory::AnsibleTower::TargetedRefresh::ServiceInstance).not_to receive(:new)

          subject.process
        end
      end
    end

    context "on not implemented operation" do
      let(:message) do
        double(:message => 'SomeModel.some_method',
               :payload => {
                 'sent_at' => Time.now.utc.iso8601,
                 'params'  => [{:task_id => 1}, {:task_id => 2}]
               }.to_json)
      end

      subject { described_class.new('SomeModel', 'some_method', JSON.parse(message.payload), nil) }

      it "logs warning with all the Task ids" do
        allow(subject).to receive(:update_tasks)

        msg = "Processing SomeModel#some_method - Task[ id: 1 | id: 2 ]: Not Implemented!"
        expect(subject.logger).to receive(:warn).with(msg)

        subject.process
      end

      it "updates all Tasks in payload" do
        %w[1 2].each do |task_id|
          expect(subject).to receive(:update_task).with(task_id,
                                                        :state   => 'completed',
                                                        :status  => 'error',
                                                        :context => {:error => 'SomeModel#some_method not implemented'})
        end

        subject.process
      end

      # Ensuring compatibility with messages like full refresh etc.
      context "with payload not based on tasks" do
        let(:message) do
          double(:message => 'SomeModel.some_method',
                 :payload => {
                   'sent_at' => Time.now.utc.iso8601,
                   'params'  => [{:source_id => 1}, {:source_id => 2}]
                 }.to_json)
        end

        it "doesn't raise an exception if payload not based on tasks" do
          expect(subject).not_to receive(:update_task)

          msg = "Processing SomeModel#some_method - Not Implemented!"
          expect(subject.logger).to receive(:warn).with(msg)

          subject.process
        end
      end
    end
  end
end
