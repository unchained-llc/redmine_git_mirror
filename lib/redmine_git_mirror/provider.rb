require 'uri'

module RedmineGitMirror
  class Provider
    attr_reader :kind, :path

    def initialize(source)
      if Settings::PROVIDERS.include?(source.to_s)
        @kind = source.to_s
      else
        remote = Remote.new(source)
        @kind = remote.host == 'github.com' ? 'github' : 'gitlab'
        raise Error, 'Repository host does not match the configured GitLab' if @kind == 'gitlab' && remote.host != URI.parse(Settings.gitlab_url).host.to_s.downcase
        @path = remote.path
        prefix = URI.parse(Settings.gitlab_url).path.sub(%r{\A/}, '') + '/' if @kind == 'gitlab'
        @path = @path.delete_prefix(prefix) if prefix && prefix != '/'
        raise Error, 'Select a GitHub repository' if @kind == 'github' && @path.split('/').length != 2
      end
      @origin = @kind == 'github' ? 'https://api.github.com' : Settings.gitlab_url + '/api/v4'
      raise Error, 'Connect this provider in the Git Mirror settings first' unless Settings.connected?(@kind)
      @resource = @kind == 'github' ? "/repos/#{@path}" : "/projects/#{URI.encode_www_form_component(@path)}" if @path
    rescue ArgumentError
      raise Error, 'Invalid repository URL'
    end

    def repositories
      endpoint = kind == 'github' ? '/user/repos?sort=full_name' : '/projects?membership=true&min_access_level=40&order_by=path&sort=asc'
      list(endpoint).map do |repo|
        {name: repo[kind == 'github' ? 'full_name' : 'path_with_namespace'],
         url: repo[kind == 'github' ? 'html_url' : 'web_url'],
         available: !repo['archived'] && (kind != 'github' || repo.dig('permissions', 'admin') == true)}
      end
    end

    def ssh_url
      repo = request(:get, @resource)
      value = repo.fetch(kind == 'github' ? 'ssh_url' : 'ssh_url_to_repo')
      expected = kind == 'github' ? 'github.com' : URI.parse(Settings.gitlab_url).host.to_s.downcase
      raise Error, 'Unexpected SSH clone URL returned by the provider' unless value.to_s.match?(%r{\A(?:ssh://|[^\s/]+@)}) && Remote.new(value).host == expected
      value
    rescue KeyError, TypeError, ArgumentError
      raise Error, 'Invalid repository response'
    end

    def ensure_key(public_key, title)
      endpoint = @resource + (kind == 'github' ? '/keys' : '/deploy_keys')
      key = list(endpoint).find { |entry| entry['key'].to_s.split[0, 2] == public_key.split[0, 2] }
      if key
        raise Error, 'The existing Deploy Key must be read-only' if kind == 'github' ? key['read_only'] != true : key['can_push'] == true
        return
      end
      body = {title: title, key: public_key}
      body[kind == 'github' ? :read_only : :can_push] = kind == 'github'
      request(:post, endpoint, body)
    end

    def ensure_webhook(url, secret, previous_url: nil)
      endpoint = @resource + '/hooks'
      hook = list(endpoint).find { |entry| [url, previous_url].compact.include?(kind == 'github' ? entry.dig('config', 'url') : entry['url']) }
      body = if kind == 'github'
        {name: 'web', active: true, events: ['push'], config: {url: url, content_type: 'json', secret: secret, insecure_ssl: '0'}}
      else
        {url: url, token: secret, push_events: true, tag_push_events: true, enable_ssl_verification: true}
      end
      request(hook ? (kind == 'github' ? :patch : :put) : :post, hook ? "#{endpoint}/#{Integer(hook.fetch('id'))}" : endpoint, body)
    end

    def remove_connection(webhook_url, public_key:, title:)
      keys_path = @resource + (kind == 'github' ? '/keys' : '/deploy_keys')
      hooks_path = @resource + '/hooks'
      # Resolve both lists before deleting anything, and only touch this mirror's
      # dedicated key (matching both title and key) and exact callback URL.
      keys = public_key ? list(keys_path).select { |key| key['title'] == title && key['key'].to_s.split[0, 2] == public_key.split[0, 2] } : []
      hooks = list(hooks_path).select { |hook| (kind == 'github' ? hook.dig('config', 'url') : hook['url']) == webhook_url }
      hooks.each { |hook| delete_resource("#{hooks_path}/#{Integer(hook.fetch('id'))}") }
      keys.each { |key| delete_resource("#{keys_path}/#{Integer(key.fetch('id'))}") }
    end

    private

    def delete_resource(path)
      request(:delete, path)
    rescue Http::ApiError => error
      raise unless error.status == 404
    end

    def list(endpoint)
      result = []
      1.upto(100) do |page|
        entries = request(:get, "#{endpoint}#{endpoint.include?('?') ? '&' : '?'}per_page=100&page=#{page}")
        raise Error, 'Invalid repository list response' unless entries.is_a?(Array)
        result.concat(entries)
        return result if entries.length < 100
      end
      raise Error, 'Too many repositories to list'
    end

    def request(method, path, body = nil)
      Http.request(method, @origin + path, token: Settings.api_token(kind), body: body)
    end
  end
end
