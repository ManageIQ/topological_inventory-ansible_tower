require 'topological_inventory/ansible_tower/collector/scheduler'
require 'timecop'

RSpec.describe TopologicalInventory::AnsibleTower::Collector::Scheduler do
  let(:source_uid) { '09d1ac7c-a9db-46d0-8a65-e8c4aafbeaa4' }
  subject { described_class.new }

  around do |example|
    ENV["COLLECTOR_FULL_REFRESH_FREQUENCY"] = '10'
    ENV["COLLECTOR_PARTIAL_REFRESH_FREQUENCY"] = '5'

    @start_time = Time.now.utc
    Timecop.freeze(@start_time)

    example.run

    Timecop.return
    ENV["COLLECTOR_FULL_REFRESH_FREQUENCY"] = nil
    ENV["COLLECTOR_PARTIAL_REFRESH_FREQUENCY"] = nil
  end

  describe "#do_full_refresh?" do
    it "returns true if no timestamp found" do
      expect(subject.do_full_refresh?(source_uid)).to be_truthy
    end

    it "returns T/F regarding last full refresh reached threshold" do
      subject.full_refresh_started!(source_uid)
      subject.full_refresh_finished!(source_uid)

      Timecop.travel(@start_time + 1.second)
      expect(subject.do_full_refresh?(source_uid)).to be_falsey

      Timecop.travel(@start_time + subject.full_refresh_frequency.seconds)
      expect(subject.do_full_refresh?(source_uid)).to be_truthy
    end
  end

  describe "#do_partial_refresh?" do
    it "returns false if full_refresh is needed" do
      subject.add_source(source_uid)

      expect(subject.do_full_refresh?(source_uid)).to be_truthy
      expect(subject.do_partial_refresh?(source_uid)).to be_falsey
    end

    it "returns T/F if full_refresh was done and last partial refresh reached threshold" do
      allow(subject).to receive(:do_full_refresh?).and_return(false)

      subject.add_source(source_uid)

      subject.partial_refresh_started!(source_uid)
      subject.partial_refresh_finished!(source_uid)

      Timecop.travel(@start_time + 1.second)
      expect(subject.do_partial_refresh?(source_uid)).to be_falsey

      Timecop.travel(@start_time + subject.partial_refresh_frequency.seconds)
      expect(subject.do_partial_refresh?(source_uid)).to be_truthy
    end
  end

  describe "#do_refresh?" do
    it "return true if either full or partial refresh needs to be run" do
      subject.add_source(source_uid)

      allow(subject).to receive(:do_full_refresh?).and_return(false)
      allow(subject).to receive(:do_partial_refresh?).and_return(false)

      expect(subject.do_refresh?(source_uid)).to be_falsey

      allow(subject).to receive(:do_full_refresh?).and_return(true)
      allow(subject).to receive(:do_partial_refresh?).and_return(false)

      expect(subject.do_refresh?(source_uid)).to be_truthy

      allow(subject).to receive(:do_full_refresh?).and_return(false)
      allow(subject).to receive(:do_partial_refresh?).and_return(false)

      expect(subject.do_refresh?(source_uid)).to be_falsey
    end
  end

  describe "#full_refresh_started!" do
    it "sets start time of full refresh" do
      subject.full_refresh_started!(source_uid)

      timestamps = subject.send(:timestamps)[source_uid]
      expect(timestamps[:full_refresh][:started_at]).to eq(@start_time)
    end
  end

  describe "#full_refresh_finished!" do
    it "sets last refresh time of both full AND partial refresh to start_time" do
      subject.full_refresh_started!(source_uid)
      Timecop.travel(@start_time + 100.seconds)
      subject.full_refresh_finished!(source_uid)

      timestamps = subject.send(:timestamps)[source_uid]
      expect(timestamps[:full_refresh][:last_finished_at]).to eq(@start_time)
      expect(timestamps[:partial_refresh][:last_finished_at]).to eq(@start_time)
    end
  end

  describe "#partial_refresh_finished!" do
    it "sets last refresh time of partial refresh" do
      subject.partial_refresh_started!(source_uid)
      Timecop.travel(@start_time + 100.seconds)
      subject.partial_refresh_finished!(source_uid)

      timestamps = subject.send(:timestamps)[source_uid]
      expect(timestamps[:full_refresh][:last_finished_at]).to be_nil
      expect(timestamps[:partial_refresh][:last_finished_at]).to eq(@start_time)
    end

    it "raises an exception if neither full nor partial refresh started before" do
      expect { subject.partial_refresh_finished!(source_uid) }.to raise_exception("Refresh started_at for source #{source_uid} is missing!")
    end
  end

  describe "#last_partial_refresh_at" do
    it "returns nil if source wasn't registered (it means full-refresh)" do
      expect(subject.last_partial_refresh_at(source_uid)).to be_nil
    end

    it "returns timestamp of last finished partial refresh" do
      subject.partial_refresh_started!(source_uid)
      subject.partial_refresh_finished!(source_uid)
      timestamps = subject.send(:timestamps)[source_uid]
      expect(timestamps[:partial_refresh][:last_finished_at]).to eq(@start_time)

      expect(subject.last_partial_refresh_at(source_uid)).to eq(@start_time)
    end

    it "returns timestamp of last finished full refresh if no partial_refresh was ran before" do
      subject.full_refresh_started!(source_uid)
      subject.full_refresh_finished!(source_uid)

      expect(subject.last_partial_refresh_at(source_uid)).to eq(@start_time)
    end
  end
end
