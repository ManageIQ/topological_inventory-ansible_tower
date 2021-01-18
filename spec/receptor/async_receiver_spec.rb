require "topological_inventory/ansible_tower/collector/metrics"

RSpec.describe TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver do
  let(:collector) { double('collector') }
  let(:entity_type) { 'service_credentials' }
  let(:parser) { TopologicalInventory::AnsibleTower::Parser.new(:tower_url => 'https://tower.example.com') }
  let(:refresh_state_started_at) { Time.now.utc }
  let(:refresh_state_uuid) { '8bebeece-5da9-4481-bbf2-9dbbaa69c048' }
  let(:service_credential) { OpenStruct.new(:id => 1, :name => 'credential1', :description => 'desc', :credential_type_id => 1) }
  let(:metrics) { instance_double(TopologicalInventory::AnsibleTower::Collector::Metrics, :record_error => nil) }

  subject { TopologicalInventory::AnsibleTower::Receptor::AsyncReceiver.new(collector, nil, entity_type, refresh_state_uuid, refresh_state_started_at) }

  before do
    allow(TopologicalInventory::AnsibleTower::Parser).to receive(:new).and_return(parser)
    allow(collector).to receive_messages(:response_received! => nil, :metrics => metrics)
  end

  describe "#on_success" do
    it "parses received data and sends them to the collector" do
      expect(parser).to receive(:parse_service_credential).with(service_credential).and_call_original
      expect(collector).to receive(:async_save_inventory).with(entity_type, refresh_state_uuid, parser)

      subject.on_success(nil, [service_credential])

      expect(subject.total_parts.value).to eq(1)
      expect(subject.sweep_scope.to_a).to eq([entity_type.to_sym])
    end

    context "with lambda" do
      let(:entity_type) { 'service_offerings' }
      let(:service_offering) { OpenStruct.new(:id => 1, :name => 'Job Template', :type => 'job_template') }

      it "makes a transformation with the data" do
        subject.transformation = lambda do |template|
          {
            :template      => template,
            :template_type => template.type.to_sym,
            :survey_spec   => nil
          }
        end
        expect(parser).to(receive(:parse_service_offering)
                            .with(:template      => service_offering,
                                  :template_type => :job_template,
                                  :survey_spec   => nil)
                            .and_call_original)

        expect(collector).to receive(:async_save_inventory)

        subject.on_success(nil, [service_offering])

        expect(subject.total_parts.value).to eq(1)
        expect(subject.sweep_scope.to_a).to eq([entity_type.to_sym])
      end
    end
  end

  context "heartbeat" do
    it "informs collector about any received message" do
      allow(collector).to receive_messages(:async_save_inventory => nil, :source => '1234')
      # 4 for each method and 1 for each entity in on_success
      expect(collector).to receive(:response_received!).exactly(5).times

      subject.on_success('1', [service_credential])
      subject.on_error('2', '1', 'Some error')
      subject.on_timeout('3')
      subject.on_eof('4')
    end
  end

  context "metrics" do
    before do
      allow(collector).to receive_messages(:async_save_inventory => nil, :response_received! => nil, :source => '12345')
    end

    it "records error in on_success" do
      allow(parser).to receive(:parse_service_credential).and_raise(ReceptorController::Client::Error, "My Error")

      expect(metrics).to receive(:record_error).with(:receptor_error_response)

      subject.on_success('1', [service_credential])
    end

    it "records error in on_error" do
      expect(metrics).to receive(:record_error).with(:receptor_error_response)

      subject.on_error('1', '1', 'Some error')
    end

    it "records error in on_timeout" do
      expect(metrics).to receive(:record_error).with(:receptor_timeout)

      subject.on_timeout('1')
    end
  end
end
