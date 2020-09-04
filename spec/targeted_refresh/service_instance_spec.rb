require "topological_inventory/ansible_tower/targeted_refresh/service_instance"

RSpec.describe TopologicalInventory::AnsibleTower::TargetedRefresh::ServiceInstance do
  describe "#refresh" do
    # TODO: Share with availability check
    let(:host_url) { 'https://cloud.redhat.com' }
    let(:sources_api_path) { '/api/sources/v3.0' }
    let(:sources_internal_api_path) { '/internal/v1.0' }
    let(:sources_api_url) { "#{host_url}#{sources_api_path}" }

    let(:external_tenant) { '11001' }
    let(:identity) { {'x-rh-identity' => Base64.strict_encode64({'identity' => {'account_number' => external_tenant, 'user' => {'is_org_admin' => true}}, 'x-rh-insights-request-id' => "111"}.to_json)} }
    let(:headers) { {'Content-Type' => 'application/json'}.merge(identity) }
    let(:source_id) { '123' }
    let(:endpoint_id) { '234' }
    let(:authentication_id) { '345' }

    let(:payload) { {'source_id' => source_id, 'source_uid' => '1', 'params' => []} }

    let(:list_endpoints_response) { "{\"data\":[{\"default\":true,\"host\":\"10.0.0.1\",\"id\":\"#{endpoint_id}\",\"path\":\"/\",\"role\":\"ansible\",\"scheme\":\"https\",\"source_id\":\"#{source_id}\",\"tenant\":\"#{external_tenant}\"}]}" }
    let(:list_endpoint_authentications_response) { "{\"data\":[{\"authtype\":\"username_password\",\"id\":\"#{authentication_id}\",\"resource_id\":\"#{endpoint_id}\",\"resource_type\":\"Endpoint\",\"username\":\"admin\",\"tenant\":\"#{external_tenant}\"}]}" }
    let(:internal_api_authentication_response) { "{\"authtype\":\"username_password\",\"id\":\"#{authentication_id}\",\"resource_id\":\"#{endpoint_id}\",\"resource_type\":\"Endpoint\",\"username\":\"admin\",\"tenant\":\"#{external_tenant}\",\"password\":\"xxx\"}" }

    subject { described_class.new(payload) }

    context "with correct payload" do
      let(:job_refs) { %w[10 20] }
      let(:payload) do
        {'source_id'  => source_id,
         'source_uid' => '3bfb8667-2b00-480b-bcbf-452bfb34a440',
         'params'     => [{'task_id' => '1', 'source_ref' => job_refs[0], 'request_context' => identity},
                          {'task_id' => '2', 'source_ref' => job_refs[1], 'request_context' => identity}]}
      end

      let(:job) do
        double(:id                      => '1',
               :type                    => 'job',
               :artifacts               => nil,
               :extra_vars_hash         => nil,
               :finished                => Time.now.utc,
               :started                 => Time.now.utc,
               :status                  => 'successful',
               :summary_fields          => double(:credentials => []),
               :unified_job_template_id => '101')
      end

      let(:workflow) do
        double(:id                      => '2',
               :type                    => 'workflow_job',
               :extra_vars_hash         => nil,
               :finished                => Time.now.utc,
               :started                 => Time.now.utc,
               :status                  => 'successful',
               :summary_fields          => double(:credentials => []),
               :unified_job_template_id => '100')
      end

      let(:service_instances) do
        [
          {:job => job, :job_type => :job},
          {:job => workflow, :job_type => :workflow_job}
        ]
      end

      before do
        # GET
        stub_get(:endpoint, list_endpoints_response)
        stub_get(:authentication, list_endpoint_authentications_response)
        stub_get(:password, internal_api_authentication_response)

        allow(subject).to receive(:connection).and_return(double('connection'))
      end

      context "with number of tasks below limit" do
        it "saves all tasks in one call" do
          stub_const("#{described_class}::REFS_PER_REQUEST_LIMIT", 10)

          expect(subject).to receive(:refresh_part).and_call_original.once
          expect(subject).to(receive(:get_service_instances)
                               .with(subject.send(:connection), :id__in => job_refs.join(','), :page_size => subject.send(:limits)['service_instances'])
                               .and_return(service_instances).once)

          expect(subject).to receive(:save_inventory).once

          subject.refresh
        end
      end

      context "with number of tasks above limit" do
        it "saves tasks in multiple calls" do
          stub_const("#{described_class}::REFS_PER_REQUEST_LIMIT", 1)

          expect(subject).to receive(:refresh_part).and_call_original.twice
          2.times do |i|
            expect(subject).to(receive(:get_service_instances)
                                 .with(subject.send(:connection), :id__in => job_refs[i], :page_size => subject.send(:limits)['service_instances'])
                                 .and_return([service_instances[i]]))
          end

          expect(subject).to receive(:save_inventory).twice

          subject.refresh
        end
      end
    end

    context "with incorrect payload" do
      let(:payload) { {'source_id' => source_id} }

      it "logs error only" do
        expect(subject.logger).to receive(:error)
        expect(subject).not_to receive(:refresh_part)

        subject.refresh
      end
    end

    def stub_get(object_type, response)
      case object_type
      when :endpoint
        stub_request(:get, "#{sources_api_url}/sources/#{source_id}/endpoints")
          .with(:headers => headers)
          .to_return(:status => 200, :body => response, :headers => {})
      when :authentication
        stub_request(:get, "#{sources_api_url}/endpoints/#{endpoint_id}/authentications")
          .with(:headers => headers)
          .to_return(:status => 200, :body => response, :headers => {})
      when :password
        stub_request(:get, "#{host_url}#{sources_internal_api_path}/authentications/#{authentication_id}?expose_encrypted_attribute%5B%5D=password")
          .with(:headers => headers)
          .to_return(:status => 200, :body => response, :headers => {})
      end
    end
  end
end
