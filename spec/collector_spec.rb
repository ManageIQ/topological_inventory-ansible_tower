require 'topological_inventory/ansible_tower/collector/scheduler'

RSpec.describe TopologicalInventory::AnsibleTower::Collector do
  let(:source_uid) { '7b901ca3-5414-4476-8d48-a722c1493de0' }
  let(:logger) { double('Logger').as_null_object }
  let(:metrics) { double('Metrics') }
  let(:scheduler) { TopologicalInventory::AnsibleTower::Collector::Scheduler.new }

  subject do
    described_class.new(source_uid,
                        metrics,
                        :poll_time => 1)

  end

  before do
    allow(subject).to receive(:logger).and_return(logger)
  end

  describe "#collect!" do
    before do
      # collect only once
      allow(subject).to receive(:standalone_mode).and_return(false)
      allow(subject).to receive(:scheduler).and_return(scheduler)
    end

    it "collects only if it's allowed by the scheduler" do
      %i[refresh_started
         refresh_finished
         ensure_collector_threads
         wait_for_collected_data].each do |method|
        expect(subject).to receive(method).and_return(nil).once
      end

      allow(scheduler).to receive(:do_refresh?).and_return(false)
      subject.collect!

      subject.send(:finished).value = false

      allow(scheduler).to receive(:do_refresh?).and_return(true)
      subject.collect!
    end
  end

  describe "#refresh_finished" do
    it "catches an exception if called without refresh_start" do
      expect(metrics).to receive(:record_error)
      subject.send(:refresh_finished, :partial_refresh)
    end
  end
end
