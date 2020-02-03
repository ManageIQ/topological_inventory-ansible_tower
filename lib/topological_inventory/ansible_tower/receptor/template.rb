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
    end
  end
end
