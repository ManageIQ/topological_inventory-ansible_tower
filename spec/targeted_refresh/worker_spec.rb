require "topological_inventory/ansible_tower/targeted_refresh/worker"

RSpec.describe TopologicalInventory::AnsibleTower::TargetedRefresh::Worker do
  let(:client) { double("ManageIQ::Messaging::Client") }
  let(:metrics) { double("Metrics", :record_error => nil) }
  let(:topic_name) { "platform.topological-inventory.collector-ansible-tower" }

  subject { described_class.new(metrics) }

  before do
    allow(subject).to receive(:client).and_return(client)
    allow(client).to receive(:close)
    TopologicalInventory::AnsibleTower::MessagingClient.class_variable_set(:@@default, nil)
  end

  describe "#run" do
    before do
      allow(TopologicalInventory::AnsibleTower::ConnectionManager).to receive_messages(:receptor_client       => nil,
                                                                                       :start_receptor_client => nil,
                                                                                       :stop_receptor_client  => nil)
    end

    it "listens on the correct queue" do
      expect(client).to receive(:subscribe_topic)
        .with(hash_including(:service => topic_name))
      expect(client).to receive(:close)

      subject.run
    end
  end

  describe "#process_message" do
    let(:message) { double(:message => 'Some.message', :payload => {:key => :value}.to_json, :ack => nil) }
    let(:message_unparsable) { double(:message => 'Some.message', :payload => '{:key => :value}', :ack => nil) }
    let(:message_non_json) { double(:message => 'Some.message', :payload => {:key => :value}, :ack => nil) }

    it "manually acks received messages" do
      allow(TopologicalInventory::AnsibleTower::TargetedRefresh::Processor).to receive(:process!)
      expect(message).to receive(:ack).once

      subject.send(:process_message, message)
    end

    it "processes payload in the JSON format" do
      expect(TopologicalInventory::AnsibleTower::TargetedRefresh::Processor).to receive(:process!)
        .with(message, {'key' => 'value'}, metrics)
      subject.send(:process_message, message)
    end

    it "logs error and metrics if payload isn't in JSON format" do
      allow(subject).to receive(:logger).and_return(double('null_object').as_null_object)
      expect(subject.logger).to receive(:error).twice
      expect(metrics).to receive(:record_error).twice

      subject.send(:process_message, message_unparsable)
      subject.send(:process_message, message_non_json)
    end
  end
end
