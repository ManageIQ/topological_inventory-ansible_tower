module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiObject
      attr_accessor :api, :connection, :klass, :uri

      include Logging

      delegate :receptor_client, :to => :connection

      RECEPTOR_DIRECTIVE = "receptor_catalog:execute".freeze

      def initialize(api, connection, type, receiver = nil)
        self.api             = api
        self.connection      = connection
        self.klass           = api.class_from_type(type.to_s.singularize)
        self.receiver        = receiver
        self.type            = type
        self.uri             = nil
      end

      # If receiver is provided, :non_blocking directive is used
      def async?
        receiver.present?
      end

      def get
        response = send_request(:get, endpoint)
        raw_kafka_response(response)
      end

      def post(data)
        response = send_request(:post, endpoint, data)
        raw_kafka_response(response)
      end

      def find(id)
        path = File.join(endpoint, id.to_s, '/')

        response = send_request(:get, path)
        build_object(parse_kafka_response(response))
      end

      def all(query_params = nil, receptor_opts = {})
        find_all_by_url(endpoint, query_params, receptor_opts)
      end

      # @param params [Hash] :page_size
      def find_all_by_url(url, params = nil, receptor_opts = {})
        if async?
          @collection = []
          send_request(:get, url, params, receptor_opts)
        else
          Enumerator.new do |yielder|
            @collection   = []
            next_page_url = url
            options       = params

            loop do
              next_page_url = fetch_more_results(next_page_url, options) if @collection.empty?
              options = nil # pagination is included in next_page response
              break if @collection.empty?

              yielder.yield(@collection.shift)
            end
          end
        end
      end

      def endpoint
        if type.index(connection.default_api_path) == 0
          # Special case for Job template's survey_spec
          # Faraday in Tower client uses URI + String merge feature
          type
        else
          File.join(connection.default_api_path, type)
        end
      end

      protected

      attr_accessor :receiver, :type

      def build_payload(http_method, path, params = nil, receptor_opts = {})
        slug = path.to_s
        payload = {
          'method'          => http_method.to_s.upcase,
          'href_slug'       => slug,
          'params'          => params,
          'fetch_all_pages' => !!receptor_opts[:fetch_all_pages]
        }
        %i[accept_encoding apply_filter].each do |opt|
          payload[opt.to_s] = receptor_opts[opt] if receptor_opts[opt]
        end

        payload
      end

      def send_request(http_method, path, params = nil, receptor_opts = {})
        payload = build_payload(http_method, path, params, receptor_opts)

        directive_type = async? ? :non_blocking : :blocking
        directive = receptor_client.directive(connection.account_number,
                                              connection.receptor_node,
                                              :directive          => RECEPTOR_DIRECTIVE,
                                              :log_message_common => payload['href_slug'],
                                              :payload            => payload.to_json,
                                              :type               => directive_type)

        if async?
          directive
            .on_success { |msg_id, response| on_success(msg_id, response) }
            .on_error { |msg_id, code, response| on_error(msg_id, code, response) }
            .on_timeout { |msg_id| on_timeout(msg_id) }
            .on_eof { |msg_id| on_eof(msg_id) }
        end

        directive.call
      end

      # Successful response callback (response type="response")
      # Can be received multiple times
      def on_success(msg_id, response)
        if receiver.respond_to?(:on_success)
          body = parse_kafka_response(response)
          collection = async_parse_result_set(body)
          unless collection.empty?
            receiver.on_success(msg_id, collection)
          end
        else
          raise NotImplementedError, "Receptor Receiver must implement 'on_success' method"
        end
      end

      # Error response callback
      def on_error(msg_id, code, response)
        if receiver.respond_to?(:on_error)
          receiver.on_error(msg_id, code, response)
        else
          raise NotImplementedError, "Receptor Receiver must implement 'on_error' method"
        end
      end

      # Timeout callback
      # Invoked if response isn't received in ReceptorController::Client::Configuration.response_timeout
      def on_timeout(msg_id)
        if receiver.respond_to?(:on_timeout)
          receiver.on_timeout(msg_id)
        else
          raise NotImplementedError, "Receptor Receiver must implement 'on_timeout' method"
        end
      end

      # EOF message callback (response type="eof")
      # Always received as the last response message
      def on_eof(msg_id)
        if receiver.respond_to?(:on_eof)
          receiver.on_eof(msg_id)
        else
          raise NotImplementedError, "Receptor Receiver must implement 'on_eof' method"
        end
      end

      # Parsing HTTP response from receptor controller
      # (returning message id)
      def parse_receptor_response(response)
        JSON.parse(response.body.to_s.presence || '{}')
      end

      def fetch_more_results(next_page_url, params)
        return if next_page_url.nil?

        response = send_request(:get, next_page_url, params)

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
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorNodeError.new, "#{msg}, response: #{response}" if response.kind_of?(String)
        # Non-hash, non-string response means unknown error
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorUnknownResponseError.new, "#{msg}, response: #{response.inspect}" unless response.kind_of?(Hash)

        # Non-standard hash response
        raise TopologicalInventory::AnsibleTower::Receptor::ReceptorKafkaResponseError.new, "#{msg}, response: #{response.inspect}" if response['status'].nil? || response['body'].nil?

        status = response['status'].to_i
        if status < 200 || status >= 300
          # Bad response error
          msg = "Response from #{uri} failed: HTTP status: #{response['status']}"
          raise TopologicalInventory::AnsibleTower::Receptor::ReceptorKafkaResponseError.new, msg
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

      # For Async it's not needed to return "next"
      # because we're using pagination on catalog-plugin side
      def async_parse_result_set(body)
        case body.class.name
        when "Array" then
          body
        when "Hash" then
          body["results"].collect { |result| build_object(result) }
        else
          []
        end
      end

      def build_object(result)
        api.class_from_type(type.to_s.singularize).new(api, result)
      end
    end
  end
end
