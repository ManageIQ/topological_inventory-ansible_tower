require "pry-byebug"

module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiObject
      attr_accessor :api, :uri

      include Logging

      RECEPTOR_DIRECTIVE    = "receptor_http:execute".freeze
      DEFAULT_TIMEOUT       = 300 # seconds

      def initialize(api, type)
        self.api             = api
        self.default_headers = tenant_header(api.tenant_account)
        self.lock_variable   = ConditionVariable.new
        self.response_data   = nil
        self.response_mutex  = Mutex.new
        self.type            = type
        self.uri             = nil
      end

      def get
        response = send_request(:get, endpoint)
        raw_kafka_response(response)
      end

      def find(id)
        path = File.join(endpoint, id.to_s, '/')

        response = send_request(:get, path)
        build_object(parse_kafka_response(response))
      end

      # @param opts [Hash] :page_size
      def all(opts = nil)
        Enumerator.new do |yielder|
          @collection   = []
          next_page_url = endpoint
          options       = opts

          loop do
            next_page_url = fetch_more_results(next_page_url, options) if @collection.empty?
            options = nil # pagination is included in next_page response
            break if @collection.empty?

            yielder.yield(@collection.shift)
          end
        end
      end

      def response_received(_message_id, data)
        response_mutex.synchronize do
          self.response_data = data
          lock_variable.signal
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

      attr_accessor :default_headers, :lock_variable, :response_data, :response_mutex, :type

      def build_payload(http_method, path, params = nil)
        self.uri = URI(api.base_url.to_s) + path.to_s
        uri.query = params.to_query if params
        headers = { 'Authorization' => "Basic #{Base64.strict_encode64("#{api.username}:#{api.password}")}"}
        verify_ssl = api.verify_ssl != OpenSSL::SSL::VERIFY_NONE #? false : true
        {
          'method'  => http_method,
          'url'     => uri,
          'headers' => headers,
          'ssl'     => verify_ssl
        }
      end

      def send_request(http_method, path, params = nil)
        payload = build_payload(http_method, path, params)
        request = build_request(:body => {
          :account   => api.tenant_account,
          :recipient => api.receptor_id,
          :payload   => payload.to_json,
          :directive => RECEPTOR_DIRECTIVE
        })

        request.on_failure do |response|
          msg = "Request to receptor(#{api.receptor_endpoint_url}) "
          msg += if response.timed_out?
                  # Timeout
                  "timed out"
                elsif response.code == 0
                  # Could not get an http response, something's wrong.
                  "failed: #{response.return_message}"
                else
                  # Received a non-successful http response.
                  "failed: HTTP #{response.code.to_s}"
                end
          # Raises exception like AnsibleTowerClient does
          raise TopologicalInventory::AnsibleTower::Receptor::ReceptorConnectionError.new(msg)
        end

        if (response = request.run).success?
          response_body = parse_receptor_response(response)
          if (msg_id = response_body['id']).present?
            api.response_worker.register_msg_id(msg_id, self)
            wait_for_kafka_response(msg_id)
          else
            logger.error("Sending #{payload['url']}: Response doesn't contain message ID (#{response.body})")
            nil
          end
        end
      end

      # Parsing HTTP response from receptor controller
      # (returning message id)
      def parse_receptor_response(response)
        JSON.parse(response.body.to_s.presence || '{}')
      end

      def wait_for_kafka_response(message_id)
        response_mutex.synchronize do
          lock_variable.wait(response_mutex, DEFAULT_TIMEOUT)

          if response_data.present?
            data           = response_data.dup
            self.response_data = nil
            data
          else
            logger.warn("Response timeout for #{message_id}, skipping")
            nil
          end
        end
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

      # Builds the HTTP request
      #
      # @option opts [Hash] :header_params Header parameters
      # @option opts [Hash] :query_params Query parameters
      # @option opts [Hash] :form_params Query parameters
      # @option opts [Object] :body HTTP body (JSON/XML)
      # @return [Typhoeus::Request] A Typhoeus Request
      def build_request(opts = {})
        http_method = :post

        header_params = default_headers.merge(opts[:header_params] || {})
        query_params = opts[:query_params] || {}
        form_params = opts[:form_params] || {}

        #update_params_for_auth! header_params, query_params, opts[:auth_names]

        req_opts = {
          :method => http_method,
          :headers => header_params,
          :params => query_params,
        }

        if [:post, :patch, :put, :delete].include?(http_method)
          req_body = build_request_body(header_params, form_params, opts[:body])
          req_opts.update :body => req_body
          #if @config.debugging
          #  @config.logger.debug "HTTP request body param ~BEGIN~\n#{req_body}\n~END~\n"
          #end
        end

        Typhoeus::Request.new(api.receptor_endpoint_url, req_opts)
      end

      # Builds the HTTP request body
      #
      # @param [Hash] header_params Header parameters
      # @param [Hash] form_params Query parameters
      # @param [Object] body HTTP body (JSON/XML)
      # @return [String] HTTP body data in the form of string
      def build_request_body(header_params, form_params, body)
        # http form
        if header_params['Content-Type'] == 'application/x-www-form-urlencoded' ||
          header_params['Content-Type'] == 'multipart/form-data'
          data = {}
          form_params.each do |key, value|
            case value
            when ::File, ::Array, nil
              # let typhoeus handle File, Array and nil parameters
              data[key] = value
            else
              data[key] = value.to_s
            end
          end
        elsif body
          data = body.is_a?(String) ? body : body.to_json
        else
          data = nil
        end
        data
      end

      def tenant_header(tenant_account)
        # {"x-rh-identity" => Base64.strict_encode64({"identity" => {"account_number" => tenant_account}}.to_json)}
        {"x-rh-identity" => "eyJpZGVudGl0eSI6IHsiYWNjb3VudF9udW1iZXIiOiAiMDAwMDAwMSIsICJpbnRlcm5hbCI6IHsib3JnX2lkIjogIjAwMDAwMSJ9fX0="}
      end

      def build_object(result)
        api.class_from_type(type.to_s.singularize).new(api, result)
      end
    end
  end
end
