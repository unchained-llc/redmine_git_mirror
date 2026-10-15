require 'minitest/autorun'
require 'minitest/mock'
require 'ostruct'
require 'tmpdir'
require 'fileutils'
require 'stringio'

module Redmine
  module Configuration
    def self.[](_key); nil; end
  end
end
%w[http remote settings oauth provider ssh git auto_setup].each { |name| require_relative "../../lib/redmine_git_mirror/#{name}" }

class ProviderTest < Minitest::Test
  def with_provider(source = 'https://github.com/team/repo')
    RedmineGitMirror::Settings.stub(:gitlab_url, 'https://gitlab.example.com') do
      RedmineGitMirror::Settings.stub(:connected?, true) { yield RedmineGitMirror::Provider.new(source) }
    end
  end

  def fake_requests(provider, &responses)
    @calls = []
    calls = @calls
    provider.define_singleton_method(:request) do |method, path, body = nil|
      calls << [method, path, body]
      responses.call(method, path, body)
    end
  end

  def test_github_key_is_read_only_and_webhook_is_push_only
    with_provider do |provider|
      fake_requests(provider) { |method, *_| method == :get ? [] : {} }
      provider.ensure_key('ssh-ed25519 AAA', 'Redmine')
      provider.ensure_webhook('https://redmine/hook', 'secret')
    end
    assert_equal true, @calls[1][2][:read_only]
    assert_equal ['push'], @calls[3][2][:events]
    assert_equal 'secret', @calls[3][2][:config][:secret]
    assert_equal '0', @calls[3][2][:config][:insecure_ssl]
  end

  def test_gitlab_nested_group_and_tag_hooks
    with_provider('git@gitlab.example.com:group/sub/repo.git') do |provider|
      fake_requests(provider) { |method, *_| method == :get ? [] : {} }
      provider.ensure_key('ssh-ed25519 AAA', 'Redmine')
      provider.ensure_webhook('https://redmine/hook', 'secret')
    end
    assert_equal '/projects/group%2Fsub%2Frepo/deploy_keys', @calls[1][1]
    assert_equal false, @calls[1][2][:can_push]
    assert_equal true, @calls[3][2][:tag_push_events]
    assert_equal true, @calls[3][2][:enable_ssl_verification]
  end

  def test_retry_reuses_existing_key_and_updates_hook
    with_provider do |provider|
      fake_requests(provider) do |_method, path, _body|
        if path.include?('/keys?')
          [{'key' => 'ssh-ed25519 AAA comment', 'read_only' => true}]
        elsif path.include?('/hooks?')
          [{'id' => 7, 'config' => {'url' => 'https://redmine/hook'}}]
        else
          {}
        end
      end
      provider.ensure_key('ssh-ed25519 AAA', 'Redmine')
      provider.ensure_webhook('https://redmine/hook', 'new-secret')
    end
    assert_equal [:get, :get, :patch], @calls.map(&:first)
    assert_equal '/repos/team/repo/hooks/7', @calls.last[1]
  end

  def test_gitlab_hook_update_uses_put
    with_provider('https://gitlab.example.com/group/repo') do |provider|
      fake_requests(provider) { |method, *_| method == :get ? [{'id' => 7, 'url' => 'https://redmine/hook'}] : {} }
      provider.ensure_webhook('https://redmine/hook', 'secret')
    end
    assert_equal :put, @calls.last[0]
  end

  def test_existing_writable_key_is_rejected
    with_provider do |provider|
      fake_requests(provider) { |*_args| [{'key' => 'ssh-ed25519 AAA', 'read_only' => false}] }
      assert_raises(RedmineGitMirror::Error) { provider.ensure_key('ssh-ed25519 AAA', 'Redmine') }
    end
  end

  def test_repository_catalog_marks_non_admin_and_archived_entries_unavailable
    with_provider('github') do |provider|
      fake_requests(provider) do |*_args|
        [{'full_name' => 'team/admin', 'html_url' => 'https://github.com/team/admin', 'permissions' => {'admin' => true}},
         {'full_name' => 'team/read', 'permissions' => {'admin' => false}},
         {'full_name' => 'team/archived', 'archived' => true, 'permissions' => {'admin' => true}}]
      end
      entries = provider.repositories
      assert_equal [true, false, false], entries.map { |entry| entry[:available] }
      assert_equal 'https://github.com/team/admin', entries.first[:url]
    end
  end

  def test_catalog_paginates
    with_provider('github') do |provider|
      fake_requests(provider) { |_method, path, _body| path.end_with?('page=1') ? Array.new(100) { {'full_name' => 'team/repo'} } : [] }
      assert_equal 100, provider.repositories.length
      assert_equal 2, @calls.length
    end
  end

  def test_unsupported_hosts_and_branch_urls_are_rejected
    ['https://github.com.evil.example/team/repo', 'https://github.com/team/repo/tree/main'].each do |url|
      assert_raises(RedmineGitMirror::Error) { with_provider(url) { flunk } }
    end
  end

  def test_provider_must_be_connected
    RedmineGitMirror::Settings.stub(:connected?, false) do
      assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Provider.new('github') }
    end
  end

  def test_ssh_host_must_match_provider
    with_provider do |provider|
      fake_requests(provider) { |*_args| {'ssh_url' => 'git@evil.example:team/repo.git'} }
      assert_raises(RedmineGitMirror::Error) { provider.ssh_url }
    end
  end

  def test_transport_independent_identity_and_invalid_input
    assert RedmineGitMirror::Remote.same?('https://github.com/team/repo.git', 'git@github.com:team/repo')
    refute RedmineGitMirror::Remote.same?('git@github.com:team/repo', 'git@github.com:other/repo')
    %w[/tmp/repo file:///tmp/repo https://user:token@github.com/team/repo https://github.com/team/../repo].each do |url|
      assert_raises(ArgumentError) { RedmineGitMirror::Remote.new(url) }
    end
  end

  def test_cleanup_only_deletes_matching_dedicated_key_and_callback
    with_provider do |provider|
      fake_requests(provider) do |method, path, _body|
        next nil if method == :delete
        if path.include?('/keys?')
          [{'id' => 1, 'title' => 'Redmine project/repo', 'key' => 'ssh-ed25519 AAA comment'},
           {'id' => 2, 'title' => 'Someone else', 'key' => 'ssh-ed25519 AAA'},
           {'id' => 3, 'title' => 'Redmine project/repo', 'key' => 'ssh-ed25519 OTHER'}]
        else
          [{'id' => 7, 'config' => {'url' => 'https://redmine/hook'}},
           {'id' => 8, 'config' => {'url' => 'https://other/hook'}}]
        end
      end
      provider.remove_connection('https://redmine/hook', public_key: 'ssh-ed25519 AAA', title: 'Redmine project/repo')
    end
    assert_equal ['/repos/team/repo/hooks/7', '/repos/team/repo/keys/1'], @calls.select { |call| call.first == :delete }.map { |call| call[1] }
  end

  def test_cleanup_checks_both_lists_before_deleting
    with_provider do |provider|
      fake_requests(provider) do |_method, path, _body|
        raise RedmineGitMirror::Http::ApiError.new('Forbidden', 403) if path.include?('/hooks?')
        [{'id' => 1, 'title' => 'Redmine project/repo', 'key' => 'ssh-ed25519 AAA'}]
      end
      assert_raises(RedmineGitMirror::Error) do
        provider.remove_connection('https://redmine/hook', public_key: 'ssh-ed25519 AAA', title: 'Redmine project/repo')
      end
    end
    assert_equal [:get, :get], @calls.map(&:first)
  end

  def test_cleanup_can_retry_after_a_resource_has_already_been_deleted
    with_provider do |provider|
      fake_requests(provider) do |method, _path, _body|
        raise RedmineGitMirror::Http::ApiError.new('Already deleted', 404) if method == :delete
        [{'id' => 7, 'config' => {'url' => 'https://redmine/hook'}}]
      end
      provider.remove_connection('https://redmine/hook', public_key: nil, title: 'Redmine project/repo')
    end
    assert_equal [:get, :delete], @calls.map(&:first)
  end
end

class HttpTest < Minitest::Test
  def test_redirects_are_not_followed_and_errors_do_not_echo_body_or_token
    http = Object.new
    [:use_ssl=, :open_timeout=, :read_timeout=].each { |name| http.define_singleton_method(name) { |_value| } }
    http.define_singleton_method(:start) { |&block| block.call(http) }
    calls = []
    http.define_singleton_method(:request) do |request|
      calls << request
      response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
      response['X-Accepted-GitHub-Permissions'] = 'administration=read'
      response
    end
    Net::HTTP.stub(:new, http) do
      error = assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Http.request(:get, 'https://api.github.com/repos/team/repo/keys', token: 'secret-token') }
      assert_includes error.message, '/repos/team/repo/keys'
      assert_includes error.message, 'administration=read'
      refute_includes error.message, 'secret-token'
    end
    assert_equal 1, calls.length
    assert_equal 'Bearer secret-token', calls.first['Authorization']
  end
end

class AutoSetupTest < Minitest::Test
  def test_prepare_does_not_register_webhook_before_commit
    repo = OpenStruct.new(url: 'https://github.com/team/repo', identifier: 'repo', project: OpenStruct.new(identifier: 'project'), root_url: '/mirrors/repo')
    provider = Minitest::Mock.new
    provider.expect(:ssh_url, 'git@github.com:team/repo.git')
    provider.expect(:kind, 'github')
    provider.expect(:path, 'team/repo')
    provider.expect(:ensure_key, nil, ['ssh-ed25519 AAA', 'Redmine project/repo'])
    fetches = []
    RedmineGitMirror::Provider.stub(:new, provider) do
      RedmineGitMirror::Ssh.stub(:automation_key, ['/key', 'ssh-ed25519 AAA']) do
        RedmineGitMirror::Git.stub(:fetch, ->(*args) { fetches << args }) { RedmineGitMirror::AutoSetup.prepare(repo) }
      end
    end
    assert_equal 'git@github.com:team/repo.git', repo.url
    assert_match /\A[0-9a-f]{64}\z/, repo.webhook_secret
    assert_equal [['/mirrors/repo', repo.url, '/key']], fetches
    provider.verify
  end

  def test_real_generated_key_is_reused
    Dir.mktmpdir do |directory|
      RedmineGitMirror::Ssh.stub(:ssh_home, directory) do
        path, key = RedmineGitMirror::Ssh.automation_key('test')
        assert_equal [path, key], RedmineGitMirror::Ssh.automation_key('test')
        assert_equal 0600, File.stat(path).mode & 0777
      end
    end
  end

  def test_cleanup_removes_generated_key_but_preserves_other_key_paths
    Dir.mktmpdir do |directory|
      RedmineGitMirror::Ssh.stub(:ssh_home, directory) do
        path, = RedmineGitMirror::Ssh.automation_key('a' * 64)
        RedmineGitMirror::Ssh.remove_key(path)
        refute File.exist?(path)
        refute File.exist?(path + '.pub')
        manual = File.join(directory, '.ssh', 'gitmirror', 'manual-key')
        File.write(manual, 'keep')
        RedmineGitMirror::Ssh.remove_key(manual)
        assert File.exist?(manual)
        outside = File.join(directory, 'auto_' + 'b' * 64)
        File.write(outside, 'keep')
        RedmineGitMirror::Ssh.remove_key(outside)
        assert File.exist?(outside)
      end
    end
  end

  def test_real_git_fetch_imports_heads_and_tags_and_prunes_deleted_refs
    Dir.mktmpdir do |directory|
      upstream = File.join(directory, 'upstream.git')
      work = File.join(directory, 'work')
      mirror = File.join(directory, 'mirror')
      command = ->(*args) { output, status = Open3.capture2e('git', *args); assert status.success?, output }
      command.call('init', '--bare', upstream)
      command.call('init', work)
      File.write(File.join(work, 'hello.txt'), 'hello')
      command.call('-C', work, 'add', 'hello.txt')
      command.call('-C', work, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '-m', 'initial')
      command.call('-C', work, 'tag', 'v1')
      command.call('-C', work, 'push', upstream, 'HEAD:refs/heads/main', 'refs/tags/v1')
      command.call('--git-dir', upstream, 'symbolic-ref', 'HEAD', 'refs/heads/main')
      url = 'file://' + upstream
      RedmineGitMirror::Remote.stub(:same?, ->(left, right) { left == right }) do
        RedmineGitMirror::Git.fetch(mirror, url, nil)
        output, status = Open3.capture2e('git', '--git-dir', mirror, 'show-ref')
        assert status.success?
        assert_includes output, 'refs/heads/main'
        assert_includes output, 'refs/tags/v1'
        head, = Open3.capture2e('git', '--git-dir', mirror, 'symbolic-ref', 'HEAD')
        assert_equal "refs/heads/main\n", head
        command.call('--git-dir', upstream, 'update-ref', '-d', 'refs/tags/v1')
        RedmineGitMirror::Git.fetch(mirror, url, nil)
        output, = Open3.capture2e('git', '--git-dir', mirror, 'show-ref')
        refute_includes output, 'refs/tags/v1'
      end
    end
  end
end

class OAuthTest < Minitest::Test
  def setup
    @old_env = ENV.to_h.select { |key, _| key.start_with?('GIT_MIRROR_') }
    %w[GITHUB GITLAB].each do |provider|
      ENV["GIT_MIRROR_#{provider}_CLIENT_ID"] = 'test-client'
      ENV["GIT_MIRROR_#{provider}_CLIENT_SECRET"] = 'test-client-secret'
    end
  end

  def teardown
    ENV.keys.grep(/^GIT_MIRROR_/).each { |key| ENV.delete(key) }
    @old_env.each { |key, value| ENV[key] = value }
  end

  def with_oauth
    RedmineGitMirror::Settings.stub(:site_url, 'https://redmine.example') do
      RedmineGitMirror::Settings.stub(:gitlab_url, 'https://gitlab.example') { yield }
    end
  end

  def test_pkce_scope_callback_and_no_secret_in_authorization_url
    with_oauth do
      url, flow = RedmineGitMirror::Oauth.begin_authorization('gitlab', 7)
      query = URI.decode_www_form(URI.parse(url).query).to_h
      assert_equal 'api', query['scope']
      assert_equal 'https://redmine.example/git_mirror/oauth/gitlab/callback', query['redirect_uri']
      assert_equal 'S256', query['code_challenge_method']
      assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(flow['verifier']), padding: false), query['code_challenge']
      refute_includes url, 'test-client-secret'
    end
  end

  def test_wrong_state_wrong_user_expired_flow_and_changed_origin_are_rejected
    with_oauth do
      _, flow = RedmineGitMirror::Oauth.begin_authorization('gitlab', 7)
      assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Oauth.finish_authorization('gitlab', flow, 'wrong', 'code', 7) }
      assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Oauth.finish_authorization('gitlab', flow, flow['state'], 'code', 8) }
      old = flow.merge('issued_at' => Time.now.to_i - 601)
      assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Oauth.finish_authorization('gitlab', old, flow['state'], 'code', 7) }
      RedmineGitMirror::Oauth.stub(:fingerprint, 'changed-application') do
        assert_raises(RedmineGitMirror::Error) { RedmineGitMirror::Oauth.finish_authorization('gitlab', flow, flow['state'], 'code', 7) }
      end
    end
  end

  def test_authorization_exchanges_code_and_stores_encrypted_credentials
    with_oauth do
      _, flow = RedmineGitMirror::Oauth.begin_authorization('github', 7)
      values = {'github_api_token' => 'old-pat'}
      requests = []
      http = ->(method, url, **args) { requests << [method, url, args]; {'access_token' => 'new-token', 'refresh_token' => 'refresh', 'expires_in' => 7200} }
      RedmineGitMirror::Http.stub(:request, http) do
        RedmineGitMirror::Settings.stub(:encrypt, ->(value) { 'encrypted:' + value }) do
          RedmineGitMirror::Settings.stub(:update, ->(&block) { block.call(values) }) do
            RedmineGitMirror::Oauth.finish_authorization('github', flow, flow['state'], 'returned-code', 7)
          end
        end
      end
      assert_equal '', values['github_api_token']
      assert values['github_oauth'].start_with?('encrypted:')
      assert_equal flow['verifier'], requests.first[2][:body][:code_verifier]
      assert_equal 'returned-code', requests.first[2][:body][:code]
    end
  end

  def test_expired_token_is_refreshed_and_rotated_credentials_are_saved
    with_oauth do
      values = {'gitlab_oauth' => JSON.generate(access_token: 'old', refresh_token: 'old-refresh', expires_at: Time.now.to_i - 10)}
      RedmineGitMirror::Settings.stub(:[], values['gitlab_oauth']) do
        RedmineGitMirror::Settings.stub(:decrypt, ->(value) { value }) do
          RedmineGitMirror::Settings.stub(:encrypt, ->(value) { value }) do
            RedmineGitMirror::Settings.stub(:update, ->(&block) { block.call(values) }) do
              RedmineGitMirror::Http.stub(:request, {'access_token' => 'new', 'refresh_token' => 'new-refresh', 'expires_in' => 7200}) do
                assert_equal 'new', RedmineGitMirror::Oauth.access_token('gitlab')
              end
            end
          end
        end
      end
      assert_equal 'new-refresh', JSON.parse(values['gitlab_oauth'])['refresh_token']
    end
  end
end
