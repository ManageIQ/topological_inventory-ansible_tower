module TopologicalInventory::AnsibleTower
  module Receptor
    class Template < ApiObject
      def launch(post_data)
        path = File.join(endpoint, id.to_s, '/')

        response = send_request(:post, path, post_data)
        parse_response(response)

        job = JSON.parse(response)

        api.jobs.find(job['job'])
      end

      # URI + String removes URI path if String starts with '/'
      # This technique is used by Faraday client
      #
      # Response from https://18.188.178.206/api/v2/api/v2/job_templates/9/survey_spec/ failed: HTTP status: 404"}
      def survey_spec
        spec_url = related['survey_spec']
        return nil unless spec_url
        api.get(spec_url).body
      rescue AnsibleTowerClient::UnlicensedFeatureError
      end
    end
  end
end
