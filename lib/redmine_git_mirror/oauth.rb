require 'securerandom'
require 'digest'
require 'base64'
require 'json'

module RedmineGitMirror
  module Oauth
    class << self
      def configured?(provider)
        Settings::PROVIDERS.include?(provider.to_s) && !client_id(provider).empty? && !client_secret(provider).empty?
      end

      def begin_authorization(provider, user_id)
        raise Error, 'Configure the OAuth application on the server first' unless configured?(provider)
        flow = {'provider' => provider.to_s, 'user_id' => user_id, 'state' => SecureRandom.hex(32),
                'verifier' => SecureRandom.urlsafe_base64(48), 'issued_at' => Time.now.to_i, 'client' => fingerprint(provider)}
        params = {client_id: client_id(provider), redirect_uri: callback_url(provider), response_type: 'code',
                  scope: provider.to_s == 'github' ? 'repo' : 'api', state: flow['state'],
                  code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(flow['verifier']), padding: false), code_challenge_method: 'S256'}
        ["#{origin(provider)}#{provider.to_s == 'github' ? '/login/oauth/authorize' : '/oauth/authorize'}?#{URI.encode_www_form(params)}", flow]
      end

      def finish_authorization(provider, flow, state, code, user_id)
        unless flow.is_a?(Hash) && flow['provider'] == provider.to_s && flow['user_id'] == user_id &&
               (0..600).cover?(Time.now.to_i - flow['issued_at'].to_i) && flow['client'] == fingerprint(provider) &&
               !state.to_s.empty? && secure_equal?(state.to_s, flow['state'].to_s) && !code.to_s.empty?
          raise Error, 'Authorization expired or did not match this session. Please connect again.'
        end
        data = exchange(provider, grant_type: 'authorization_code', code: code, code_verifier: flow.fetch('verifier'))
        Settings.update do |values|
          values["#{provider}_oauth"] = Settings.encrypt(JSON.generate(credentials(data)))
          values["#{provider}_api_token"] = ''
        end
      end

      def access_token(provider)
        data = read_credentials(Settings["#{provider}_oauth"])
        return data.fetch('access_token') unless expired?(data)
        token = nil
        # GitLab rotates refresh tokens. Serialize refresh and reread after the lock.
        Settings.update do |values|
          data = read_credentials(values["#{provider}_oauth"])
          if expired?(data)
            raise Error, 'Connection expired. Please connect again.' if data['refresh_token'].to_s.empty?
            data = credentials(exchange(provider, grant_type: 'refresh_token', refresh_token: data['refresh_token']))
            values["#{provider}_oauth"] = Settings.encrypt(JSON.generate(data))
          end
          token = data.fetch('access_token')
        end
        token
      end

      def callback_url(provider)
        "#{Settings.site_url}/git_mirror/oauth/#{provider}/callback"
      end

      private

      def origin(provider)
        raise Error, 'Unknown provider' unless Settings::PROVIDERS.include?(provider.to_s)
        provider.to_s == 'github' ? 'https://github.com' : Settings.gitlab_url
      end

      def client_id(provider)
        ENV["GIT_MIRROR_#{provider.to_s.upcase}_CLIENT_ID"].to_s
      end

      def client_secret(provider)
        ENV["GIT_MIRROR_#{provider.to_s.upcase}_CLIENT_SECRET"].to_s
      end

      def fingerprint(provider)
        Digest::SHA256.hexdigest([client_id(provider), origin(provider), callback_url(provider)].join('\n'))
      end

      def secure_equal?(left, right)
        a, b = Digest::SHA256.digest(left).bytes, Digest::SHA256.digest(right).bytes
        difference = 0
        a.zip(b) { |x, y| difference |= x ^ y }
        difference.zero?
      end

      def exchange(provider, parameters)
        raise Error, 'OAuth application is not configured' unless configured?(provider)
        endpoint = origin(provider) + (provider.to_s == 'github' ? '/login/oauth/access_token' : '/oauth/token')
        Http.request(:post, endpoint, body: parameters.merge(client_id: client_id(provider), client_secret: client_secret(provider), redirect_uri: callback_url(provider)))
      end

      def credentials(data)
        raise Error, 'No access token was returned by the provider' unless data.is_a?(Hash) && !data['access_token'].to_s.empty?
        result = data.slice('access_token', 'refresh_token')
        result['expires_at'] = Time.now.to_i + Integer(data['expires_in']) if data['expires_in']
        result
      end

      def read_credentials(value)
        data = JSON.parse(Settings.decrypt(value.to_s))
        raise Error, 'Connection is invalid. Please connect again.' if data['access_token'].to_s.empty?
        data
      rescue JSON::ParserError, TypeError
        raise Error, 'Connection is invalid. Please connect again.'
      end

      def expired?(data)
        data['expires_at'] && data['expires_at'].to_i <= Time.now.to_i + 60
      end
    end
  end
end
