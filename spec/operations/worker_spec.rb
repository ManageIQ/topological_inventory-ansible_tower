require "topological_inventory/ansible_tower/operations/worker"

RSpec.describe TopologicalInventory::AnsibleTower::Operations::Worker do
  describe "#run" do
    let(:async_worker) { double("Async worker") }
    let(:client) { double("ManageIQ::Messaging::Client") }
    let(:message) { double("ManageIQ::Messaging::ReceivedMessage") }
    let(:metrics) { double("Metrics", :record_operation => nil) }
    let(:operation) { 'Test.operation' }
    let(:task_id) { '1' }

    subject { described_class.new(metrics) }

    before do
      require "manageiq-messaging"
      allow(TopologicalInventory::AnsibleTower::ConnectionManager).to receive_messages(:start_receptor_client => nil,
                                                                                       :stop_receptor_client  => nil)
      allow(subject).to receive(:async_worker).and_return(async_worker)
      allow(async_worker).to receive_messages(:start => nil, :stop => nil)

      allow(subject).to receive(:client).and_return(client)
      allow(client).to receive(:close)
      allow(TopologicalInventory::Providers::Common::Operations::HealthCheck).to receive(:touch_file)
      allow(message).to receive_messages(:ack => nil, :message => operation, :payload => {'params' => {'task_id' => task_id}})

      allow(subject).to receive(:logger).and_return(double('null_object').as_null_object)
      TopologicalInventory::AnsibleTower::MessagingClient.class_variable_set(:@@default, nil)
    end

    context "sync processing" do
      it "calls subscribe_messages on the right queue" do
        operations_topic = "platform.topological-inventory.operations-ansible-tower"

        expect(client).to receive(:subscribe_topic)
          .with(hash_including(:service => operations_topic)).and_yield(message)
        expect(TopologicalInventory::AnsibleTower::Operations::Processor)
          .to receive(:process!).with(message, metrics)

        expect(async_worker).not_to receive(:enqueue)

        subject.run
      end
    end

    context "async processing" do
      let(:operation) { "Source.availability_check" }

      it "enqueues message in async worker" do
        expect(async_worker).to receive(:enqueue).with(message)
        expect(subject).not_to receive(:process_message)

        operations_topic = "platform.topological-inventory.operations-ansible-tower"

        expect(client).to(receive(:subscribe_topic)
                            .with(hash_including(:service => operations_topic)).and_yield(message))

        subject.run
      end
    end

    context ".metrics" do
      it "records successful operation" do
        result = subject.operation_status[:success]

        allow(TopologicalInventory::AnsibleTower::Operations::Processor).to receive(:process!).and_return(result)
        expect(metrics).to receive(:record_operation).with(operation, :status => result)

        subject.send(:process_message, message)
      end

      it "records exception" do
        result = subject.operation_status[:error]

        allow(TopologicalInventory::AnsibleTower::Operations::Processor).to receive(:process!).and_raise("Test Exception!")
        expect(metrics).to receive(:record_operation).with(operation, :status => result)

        subject.send(:process_message, message)
      end
    end
  end
end
