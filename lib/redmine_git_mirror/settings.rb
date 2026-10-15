require 'uri'

module RedmineGitMirror
  module Settings
    PROVIDERS = %w[github gitlab].freeze
    DEFAULT = {custom_path: nil, github_api_token: '', gitlab_api_token: '', gitlab_url: 'https://gitlab.com'}.freeze

    class << self
      def [](key)
        values = Setting.plugin_redmine_git_mirror || {}
        values.fetch(key.to_s) { values.fetch(key.to_sym) { DEFAULT[key.to_sym] } }
      end

      def path
        value = self[:custom_path].to_s.strip
        value.empty? || value == '/' ? default_path : File.expand_path(value)
      end

      def default_path
        # Keep mirrors outside the plugin directory so code updates cannot remove them.
        File.join(Rails.root.to_s, 'files', 'git_mirrors')
      end

      def gitlab_url
        value = self[:gitlab_url].to_s.strip.sub(%r{/+\z}, '')
        uri = URI.parse(value)
        raise Error, 'GitLab URL must use HTTPS' unless uri.scheme == 'https' && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        value
      rescue URI::InvalidURIError
        raise Error, 'Invalid GitLab URL'
      end

      def site_url
        base = "#{Setting.protocol}://#{Setting.host_name}".sub(%r{/+\z}, '')
        uri = URI.parse(base)
        raise Error, 'Configure the Redmine host name and protocol' unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        root = Rails.application.config.relative_url_root.to_s.sub(%r{/+\z}, '')
        base += root unless root.empty? || uri.path.to_s.sub(%r{/+\z}, '') == root
        base
      rescue URI::InvalidURIError
        raise Error, 'Invalid Redmine host name'
      end

      def webhook_url(project, repository)
        "#{site_url}/sys/git_mirror/webhook/#{project}/#{repository}"
      end

      def connected?(provider)
        !self["#{provider}_api_token"].to_s.empty? || !self["#{provider}_oauth"].to_s.empty?
      end

      def api_token(provider)
        oauth = self["#{provider}_oauth"].to_s
        oauth.empty? ? decrypt(self["#{provider}_api_token"].to_s) : Oauth.access_token(provider)
      end

      def encrypt(value)
        encryptor.encrypt_and_sign(value)
      end

      def decrypt(value)
        return '' if value.empty?
        encryptor.decrypt_and_verify(value)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        raise Error, 'Cannot decrypt the connection. Reconnect in the Git Mirror settings.'
      end

      def update
        Setting.transaction do
          row = Setting.find_by(name: 'plugin_redmine_git_mirror')
          row.lock! if row
          Setting.clear_cache
          values = (Setting.plugin_redmine_git_mirror || {}).deep_dup.stringify_keys
          yield values
          Setting.plugin_redmine_git_mirror = values
          Setting.clear_cache
        end
      end

      private

      def encryptor
        require 'active_support/message_encryptor'
        key = Rails.application.key_generator.generate_key('redmine_git_mirror/api_tokens', 32)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end
  end
end
