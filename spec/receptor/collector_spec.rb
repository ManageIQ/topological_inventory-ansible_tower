require 'topological_inventory/ansible_tower/collector/scheduler'
require 'topological_inventory/ansible_tower/receptor/async_receiver'
require 'timecop'

RSpec.describe TopologicalInventory::AnsibleTower::Receptor::Collector do
  let(:account_number) { '1234' }
  let(:inventory_name) { 'AnsibleTower' }
  let(:schema_name) { 'Default' }
  let(:metrics) { double('metrics') }
  let(:receptor_node) { 'sample-node' }
  let(:scheduler) { TopologicalInventory::AnsibleTower::Collector::Scheduler.new }
  let(:source_uid) { '7b901ca3-5414-4476-8d48-a722c1493de0' }

  subject { described_class.new(source_uid, receptor_node, account_number, metrics) }

  before do
    allow(subject).to receive(:scheduler).and_return(scheduler)
  end

  describe "#connection_for_entity_type" do
    before do
      allow(TopologicalInventory::AnsibleTower::ConnectionManager).to receive(:receptor_client).and_return(double(:identity_header= => nil))
    end

    it "initializes receptor connection" do
      expect(subject.connection_for_entity_type('')).to be_instance_of(TopologicalInventory::AnsibleTower::Receptor::Connection)
    end
  end

  describe "#collector_thread" do
    let(:connection) { double('Connection') }
    let(:entity_type) { 'service_offerings' }
    let(:receiver) { double('Async receiver') }

    context "running full-refresh" do
      before do
        allow(scheduler).to receive(:do_partial_refresh?).and_return(false)
      end

      it "invokes on-premise requests" do
        expect(TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver).to receive(:new).and_return(receiver)

        expect(subject).to(receive(:get_service_offerings)
                             .with(connection,
                                   {:page_size => subject.send(:limits)[entity_type]},
                                   {:on_premise        => true,
                                    :receptor_receiver => receiver,
                                    :receptor_params   => {:accept_encoding => 'gzip', :fetch_all_pages => true}}))

        subject.collector_thread(connection, entity_type)
      end
    end

    context "running partial-refresh" do
      before do
        @start_time = Time.now.utc
        Timecop.freeze(@start_time)

        scheduler.full_refresh_started!(source_uid)
        scheduler.full_refresh_finished!(source_uid)

        Timecop.travel(@start_time + scheduler.send(:partial_refresh_frequency))
        scheduler.partial_refresh_started!(source_uid)
      end

      after { Timecop.return }

      it "creates receiver with sweeping disabled and querying with timestamp" do
        receiver_class = TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver
        expect(receiver_class).to(receive(:new)
                                    .with(subject,
                                          connection,
                                          entity_type,
                                          anything, anything,
                                          :sweeping_enabled => false)
                                    .and_return(receiver))

        expect(subject).to(receive(:get_service_offerings)
                             .with(connection,
                                   {:page_size    => subject.send(:limits)[entity_type],
                                    :modified__gt => @start_time.iso8601},
                                   {:on_premise        => true,
                                    :receptor_receiver => receiver,
                                    :receptor_params   => {:accept_encoding => 'gzip', :fetch_all_pages => true}}))

        subject.collector_thread(connection, entity_type)
      end
    end
  end

  describe "#async_collecting_finished" do
    it "only logs finish message" do
      expect(TopologicalInventory::AnsibleTower.logger).to receive(:collecting)

      subject.async_collecting_finished('some_entity', '1', '1')
    end
  end

  describe "#async_save_inventory" do
    let(:now) { Time.now.utc }
    let(:parser) { double('Parser', :collections => {:k1 => :v1, :k2 => :v2}) }

    it "saves data in parser" do
      allow(Time).to receive(:now).and_return(now)
      allow(SecureRandom).to receive(:uuid).and_return('refresh_state_part_uuid')

      expect(subject).to receive(:save_inventory).with(%i[v1 v2], inventory_name, schema_name, 'refresh_state_uuid', 'refresh_state_part_uuid', now)
      subject.async_save_inventory('some_entity', 'refresh_state_uuid', parser)
    end
  end

  describe "#async_sweep_inventory" do
    let(:total_parts) { 5 }
    it "logs and calls sweep" do
      now = Time.now.utc
      expect(TopologicalInventory::AnsibleTower.logger).to receive(:sweeping).twice

      expect(subject).to receive(:sweep_inventory).with(inventory_name, schema_name, 'refresh_state_uuid', total_parts, 'sweep_scope', now)
      subject.async_sweep_inventory('some_entity', 'refresh_state_uuid', 'sweep_scope', total_parts, now)
    end
  end
end
