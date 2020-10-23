require "topological_inventory/ansible_tower/operations/source"
require File.join(Gem::Specification.find_by_name("topological_inventory-providers-common").gem_dir, "spec/support/shared/availability_check.rb")

RSpec.describe(TopologicalInventory::AnsibleTower::Operations::Source) do
  it_behaves_like "availability_check" # in providers-common

  context "#connection_check" do
    let(:receptor_client) { double }

    subject { described_class.new({:external_tenant => "000001"}, nil).send(:connection_check) }

    before do
      allow(receptor_client).to receive(:identity_header=).and_return(nil)
    end

    context "cloud based tower" do
      let(:api_client) { instance_double(TopologicalInventory::Providers::Common::SourcesApiClient) }
      let(:default_response) { {:status => 200, :body => {}.to_json, :headers => {}} }
      let(:tower_host) { "test.tower.com" }

      before do
        allow(TopologicalInventory::Providers::Common::SourcesApiClient).to receive(:new).and_return(api_client)
        allow(api_client).to receive(:fetch_authentication).and_return(OpenStruct.new(:username => "test", :password => "xxx"))
        allow(api_client).to receive(:fetch_default_endpoint).and_return(OpenStruct.new(:host => tower_host, :port => port))
      end

      context "with a port" do
        let(:port) { 9443 }

        it "reaches out on defined port" do
          stub_request(:get, "https://test.tower.com:9443/api/v2/config/").to_return(**default_response)
          subject

          expect(a_request(:get, "https://test.tower.com:9443/api/v2/config/")).to have_been_made.at_least_once
        end
      end

      context "without a port" do
        let(:port) { nil }

        it "does not have a port in the URL" do
          stub_request(:get, "https://test.tower.com/api/v2/config/").to_return(**default_response)
          subject

          expect(a_request(:get, "https://test.tower.com/api/v2/config/")).to have_been_made.at_least_once
        end
      end
    end

    context "receptor based tower" do
      let(:api_client) { instance_double(TopologicalInventory::Providers::Common::SourcesApiClient) }
      let(:default_response) { {:status => 200, :body => {}.to_json, :headers => {}} }
      let(:directive) { double('Directive', :call => nil) }

      before do
        allow(TopologicalInventory::Providers::Common::SourcesApiClient).to receive(:new).and_return(api_client)
        allow(TopologicalInventory::AnsibleTower::ConnectionManager).to receive(:receptor_client).and_return(receptor_client)
        allow(api_client).to receive(:fetch_authentication).and_return(TopologicalInventory::Providers::Common::Operations::Source::AUTH_NOT_NECESSARY)
        allow(api_client).to receive(:fetch_default_endpoint).and_return(OpenStruct.new(:receptor_node => "test-catalog"))
        allow(receptor_client).to receive(:directive).and_return(directive)
      end

      it "hits the receptor controller" do
        expect(receptor_client).to receive(:directive).with(
          nil,
          "test-catalog",
          :directive => "receptor_catalog:execute", :log_message_common => "/api/v2/config", :payload => "{\"method\":\"GET\",\"href_slug\":\"/api/v2/config\",\"params\":null,\"fetch_all_pages\":false}",
           :type => :blocking
        ).once
        subject
      end
    end
  end
end
