module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiObject
      attr_accessor :api, :uri

      include Logging

      delegate :receptor_client, :to => :api

      RECEPTOR_DIRECTIVE    = "receptor_http:execute".freeze

      def initialize(api, type)
        self.api             = api
        self.type            = type
        self.uri             = nil
      end

      def get
        response = send_request(:get, endpoint)
        raw_kafka_response(response)
      end

      def post(data)
        response = send_request(:post, endpoint, :data => data)
        raw_kafka_response(response)
      end

      def find(id)
        path = File.join(endpoint, id.to_s, '/')

        response = send_request(:get, path)
        build_object(parse_kafka_response(response))
      end

      def all(opts = nil)
        find_all_by_url(endpoint, opts)
      end

      # @param opts [Hash] :page_size
      def find_all_by_url(url, opts = nil)
        Enumerator.new do |yielder|
          @collection   = []
          next_page_url = url
          options       = opts

          loop do
            next_page_url = fetch_more_results(next_page_url, options) if @collection.empty?
            options = nil # pagination is included in next_page response
            break if @collection.empty?

            yielder.yield(@collection.shift)
          end
        end
      end

      def endpoint
        if type.index(api.default_api_path) == 0
          # Special case for Job template's survey_spec
          # Faraday in Tower client uses URI + String merge feature
          type
        else
          File.join(api.default_api_path, type)
        end
      end

      protected

      attr_accessor :type

      def build_payload(http_method, path, query_params: nil, data: nil)
        self.uri = URI(api.base_url.to_s) + path.to_s
        uri.query = query_params.to_query if query_params
        headers = { 'Authorization' => "Basic #{Base64.strict_encode64("#{api.username}:#{api.password}")}"}
        verify_ssl = api.verify_ssl != OpenSSL::SSL::VERIFY_NONE #? false : true
        payload = {
          'method'  => http_method,
          'url'     => uri,
          'headers' => headers,
          'ssl'     => verify_ssl
        }
        payload['data'] = data if data.present?

        payload
      end

      def send_request(http_method, path, query_params: nil, data: nil)
        payload = build_payload(http_method, path, :query_params => query_params, :data => data)

        directive = receptor_client.directive(api.account_number,
                                              api.receptor_node,
                                              :directive          => RECEPTOR_DIRECTIVE,
                                              :log_message_common => payload['url'],
                                              :payload            => payload.to_json,
                                              :type               => :blocking)
        directive.call
      end

      # Parsing HTTP response from receptor controller
      # (returning message id)
      def parse_receptor_response(response)
        JSON.parse(response.body.to_s.presence || '{}')
      end

      def fetch_more_results(next_page_url, params)
        return if next_page_url.nil?

        response = send_request(:get, next_page_url, :query_params => params)

        body = parse_kafka_response(response)
        parse_result_set(body)
      end

      def parse_kafka_response(response)
        check_kafka_response(response)

        JSON.parse(response['body'])
      end

      def raw_kafka_response(response)
        check_kafka_response(response)

        Response.new(response)
      end

      def check_kafka_response(response)
        msg = "URI: #{uri}"
        # Error returned by receptor node
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorNodeError.new("#{msg}, response: #{response}") if response.kind_of?(String)
        # Non-hash, non-string response means unknown error
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorUnknownResponseError.new("#{msg}, response: #{response.inspect}") unless response.kind_of?(Hash)

        # Non-standard hash response
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorKafkaResponseError.new("#{msg}, response: #{response.inspect}") if response['status'].nil? || response['body'].nil?

        status = response['status'].to_i
        if status < 200 || status >= 300
          # Bad response error
          msg = "Response from #{uri} failed: HTTP status: #{response['status']}"
          raise TopologicalInventory::AnsibleTower::Receptor::ReceptorKafkaResponseError.new(msg)
        end
      end

      def parse_result_set(body)
        case body.class.name
        when "Array" then
          @collection = body
          nil
        when "Hash" then
          body["results"].each { |result| @collection << build_object(result) }
          body["next"]
        end
      end

      def build_object(result)
        api.class_from_type(type.to_s.singularize).new(api, result)
      end
    end
  end
end
