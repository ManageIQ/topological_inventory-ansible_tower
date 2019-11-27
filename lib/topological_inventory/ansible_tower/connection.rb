require "openssl"
require "ansible_tower_client"

module TopologicalInventory::AnsibleTower
  class Connection
    include Logging

    def connect(base_url, username, password,
                proxy_hostname:, receptor_node_id:,
                verify_ssl: ::OpenSSL::SSL::VERIFY_NONE)
      AnsibleTowerClient.logger = self.logger

      url = proxy_hostname.present? ? api_url(proxy_hostname) : api_url(base_url)

      connection_opts = {
        :base_url   => url,
        :username   => username,
        :password   => password,
        :verify_ssl => verify_ssl,
        :headers    => {}
      }
      connection_opts[:headers]['x-rh-receptor'] = receptor_node_id if receptor_node_id.present?
      connection_opts[:headers]['x-rh-endpoint'] = CGI.escape(api_url(base_url)) if proxy_hostname.present?

      AnsibleTowerClient::Connection.new(connection_opts)
    end

    def api_url(base_url)
      base_url = "https://#{base_url}" unless base_url =~ %r{\Ahttps?:\/\/} # HACK: URI can't properly parse a URL with no scheme
      uri      = URI(base_url)
      uri.path = default_api_path if uri.path.blank?
      uri.to_s
    end

    private

    def default_api_path
      "/api/v1".freeze
    end
  end
end
