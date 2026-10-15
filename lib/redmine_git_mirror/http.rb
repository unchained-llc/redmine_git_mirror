require 'net/http'
require 'json'
require 'openssl'

module RedmineGitMirror
  class Error < StandardError; end

  module Http
    class ApiError < Error
      attr_reader :status
      def initialize(message, status)
        @status = status.to_i
        super(message)
      end
    end

    def self.request(method, url, token: nil, body: nil)
      uri = URI.parse(url)
      raise Error, 'API URL must use HTTPS' unless uri.scheme == 'https' && uri.host && !uri.userinfo
      klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, put: Net::HTTP::Put, delete: Net::HTTP::Delete}.fetch(method)
      request = klass.new(uri.request_uri)
      request['Accept'] = 'application/json'
      request['User-Agent'] = 'Redmine-Git-Mirror'
      request['Authorization'] = "Bearer #{token}" if token
      if body
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      response = http.start { |connection| connection.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        permissions = response['X-Accepted-GitHub-Permissions'].to_s.scan(/[a-z_]+=(?:read|write)/).join(', ')
        detail = permissions.empty? ? '' : "; required permissions: #{permissions}"
        raise ApiError.new("#{method.to_s.upcase} #{uri.path}: HTTP #{response.code}#{detail}", response.code)
      end
      return nil if response.code == '204'
      data = JSON.parse(response.body)
      raise Error, 'OAuth authorization was rejected' if data.is_a?(Hash) && data['error']
      data
    rescue JSON::ParserError
      raise Error, 'Invalid API response'
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
      raise Error, 'Cannot connect to the Git provider; check the host, TLS certificate and network'
    end
  end
end
