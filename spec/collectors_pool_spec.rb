require 'topological_inventory/ansible_tower/collector/scheduler'

RSpec.describe TopologicalInventory::AnsibleTower::CollectorsPool do
  let(:source) { double("Source") }

  subject { described_class.new(nil, nil) }

  describe ".source_valid?" do
    context "public tower collector" do
      it "returns false if any of source, host, username, password are blank" do
        (-1..3).each do |nil_index|
          data = (0..3).collect { |j| nil_index == j ? nil : 'some_data' }
          allow(source).to receive_messages(:source        => data[0],
                                            :host          => data[1],
                                            :receptor_node => nil)
          secret = {"username" => data[2], "password" => data[3]}

          expect(subject.source_valid?(source, secret)).to eq(nil_index == -1)
        end
      end
    end

    context "on-premise tower collector" do
      it "returns false if any of source, receptor_node are blank" do
        (-1..1).each do |nil_index|
          data = (0..1).collect { |j| nil_index == j ? nil : 'some_data' }
          allow(source).to receive_messages(:source        => data[0],
                                            :host          => nil,
                                            :receptor_node => data[1])
          expect(subject.source_valid?(source, {})).to eq(nil_index == -1)
        end
      end
    end
  end

  describe ".new_collector" do
    let(:scheduler) { TopologicalInventory::AnsibleTower::Collector::Scheduler.new }

    before do
      allow(subject).to receive(:scheduler).and_return(scheduler)
    end

    it "creates public tower's collector if receptor_node blank" do
      allow(source).to receive_messages(:source        => SecureRandom.uuid,
                                        :scheme        => 'http',
                                        :host          => 'www.example.com',
                                        :port          => 80,
                                        :receptor_node => nil)
      secret = {'username' => 'redhat', 'password' => 'secret_password'}

      expect(scheduler).to receive(:add_source).with(source.source)

      collector = subject.new_collector(source, secret)
      expect(collector).to be_instance_of(TopologicalInventory::AnsibleTower::Cloud::Collector)
    end

    it "creates on-premise tower's collector if receptor_node present" do
      allow(source).to receive_messages(:source         => SecureRandom.uuid,
                                        :account_number => '123456',
                                        :receptor_node  => 'sample-node')

      expect(scheduler).to receive(:add_source).with(source.source)

      collector = subject.new_collector(source, {})
      expect(collector).to be_instance_of(TopologicalInventory::AnsibleTower::Receptor::Collector)
    end
  end
end
