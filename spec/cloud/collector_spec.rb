require 'topological_inventory/ansible_tower/collector/scheduler'
require 'timecop'

describe TopologicalInventory::AnsibleTower::Cloud::Collector do
  let(:connection) { double('connection') }
  let(:scheduler) { TopologicalInventory::AnsibleTower::Collector::Scheduler.new }
  let(:source_uid) { '7b901ca3-5414-4476-8d48-a722c1493de0' }

  subject do
    described_class.new(source_uid,
                        'tower.example.com',
                        'user', 'passwd',
                        nil)
  end

  context "on partial refresh" do
    before do
      allow(subject).to receive(:scheduler).and_return(scheduler)
    end

    describe "#collector_thread" do
      let(:entity_type) { 'service_offerings' }

      before do
        @start_time = Time.now.utc
        Timecop.freeze(@start_time)

        scheduler.full_refresh_started!(source_uid)
        scheduler.full_refresh_finished!(source_uid)

        Timecop.travel(@start_time + scheduler.send(:partial_refresh_frequency))
        scheduler.partial_refresh_started!(source_uid)
      end

      after do
        Timecop.return
      end

      it "creates API call with timestamp when partial refresh" do
        expect(subject.send(:last_modified_at)).to eq(@start_time.iso8601)

        expect(subject).to(receive(:get_service_offerings)
                             .with(connection, hash_including(:modified__gt => @start_time.iso8601))
                             .and_return([]))
        subject.send(:collector_thread, connection, entity_type)
      end

      it "skips sweeping when partial refresh" do
        allow(subject).to(receive(:get_service_offerings).twice.and_return([]))

        expect(subject).to receive(:sweep_inventory).once

        subject.send(:collector_thread, double('connection'), entity_type)

        allow(scheduler).to receive(:do_partial_refresh?).and_return(false)
        subject.send(:collector_thread, double('connection'), entity_type)
      end
    end
  end
end
