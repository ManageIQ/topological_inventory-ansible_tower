module TopologicalInventory::AnsibleTower
  module Receptor
    class ApiObject
      attr_accessor :api, :endpoint

      include Logging

      POLL_TIME             = 5 # seconds
      RECEPTOR_DIRECTIVE    = "receptor_http:execute".freeze
      RECEPTOR_REQUEST_PATH = "proxy".freeze # TODO: For testing purposes
      DEFAULT_TIMEOUT       = 300.seconds

      def initialize(api, endpoint)
        self.api = api
        self.endpoint = endpoint
        @response_mutex = Mutex.new
        @cv = ConditionVariable.new
        @response_data = nil

        @default_headers = {}
      end

      def find(id)
        path = File.join(endpoint, id.to_s, '/')

        response = send_request(:get, path)
        parse_response(response)
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

      def response_received(message_id, data)
        @response_mutex.synchronize do
          @response_data = data
          @cv.signal
        end
      end

      protected

      def build_payload(http_method, path, params = nil)
        uri = URI(api.base_url.to_s) + path.to_s
        uri.query = params if params
        headers = {}
        {
          'method'  => http_method,
          'url'     => uri,
          'headers' => headers,
          'ssl'     => api.verify_ssl # || false
        }
      end

      def send_request(http_method, path, params = nil)
        payload = build_payload(http_method, path, params)
        request = build_request(:body => {
          :recipient => api.receptor_id,
          :payload   => payload.to_json,
          :directive => RECEPTOR_DIRECTIVE
        })

        request.on_complete do |response|
          if response.success?
            # Successful request
            response_body = parse_response(response)
            # TODO: needs more info
            if (msg_id = response_body[:message_id]).present?
              api.response_worker.register_msg_id(msg_id, self)
              wait_for_response(msg_id)
            else
              logger.error("Sending #{payload['url']}: Response doesn't contain message ID (#{response.body})")
            end
          elsif response.timed_out?
            # Timeout
            logger.error("Sending #{payload['url']} timed out")
          elsif response.code == 0
            # Could not get an http response, something's wrong.
            logger.error("Sending #{payload['url']} failed: #{response.return_message}")
          else
            # Received a non-successful http response.
            logger.error("Sending #{payload['url']} failed: HTTP status #{response.code.to_s}")
          end
        end

        request.run
      end

      # TODO: needs more info
      def parse_response(response)
        JSON.parse(response.body.to_s.presence || '{}')
      end

      def wait_for_response(message_id)
        @response_mutex.synchronize do
          @cv.wait(@response_mutex, DEFAULT_TIMEOUT)

          if @response_data.present?
            data           = @response_data.dup
            @response_data = nil
            return data
          else
            logger.warn("Response timeout for #{message_id}, skipping")
          end
        end
      end

      def fetch_more_results(next_page_url, params)
        return if next_page_url.nil?

        response = send_request(:get, next_page_url, params)

        body = parse_response(response)
        parse_result_set(body)
      end

      def parse_result_set(body)
        case body.class.name
        when "Array" then
          @collection = body
          nil
        when "Hash" then
          body["results"].each { |result| @collection << result }
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
        # TODO: needs ack from receptor-controller
        url = File.join(api.receptor_endpoint_url, RECEPTOR_REQUEST_PATH)
        http_method = 'POST'

        header_params = @default_headers.merge(opts[:header_params] || {})
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

        Typhoeus::Request.new(url, req_opts)
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
    end
  end
end
