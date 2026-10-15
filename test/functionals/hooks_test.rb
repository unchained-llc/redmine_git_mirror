require File.expand_path('../../test_helper', __FILE__)

class HooksTest < Redmine::IntegrationTest
  fixtures :users, :projects, :enabled_modules

  setup do
    Setting.enabled_scm = %w[GitMirror]
    User.current = User.find(1)
    RedmineGitMirror::Settings.stubs(:connected?).returns(true)
    RedmineGitMirror::AutoSetup.stubs(:prepare)
    RedmineGitMirror::AutoSetup.stubs(:webhook)
    Repository::GitMirror.any_instance.stubs(:fetch_changesets)
    @repository = Repository::GitMirror.create!(project: Project.find(1), identifier: 'hook-test', url: 'git@github.com:team/repo.git', webhook_secret: 'test-secret')
    @path = '/sys/git_mirror/webhook/ecookbook/hook-test'
  end

  teardown { User.current = nil }

  test 'ping is acknowledged without fetching' do
    Repository::GitMirror.any_instance.expects(:sync!).never
    body = {hook_id: 7}.to_json
    signature = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', 'test-secret', body)
    post @path, params: body, headers: {'CONTENT_TYPE' => 'application/json', 'X-GitHub-Event' => 'ping', 'X-Hub-Signature-256' => signature}
    assert_response :ok
  end

  test 'invalid signature is rejected' do
    Repository::GitMirror.any_instance.expects(:sync!).never
    post @path, params: '{}', headers: {'CONTENT_TYPE' => 'application/json', 'X-GitHub-Event' => 'push', 'X-Hub-Signature-256' => 'sha256=invalid'}
    assert_response :unauthorized
  end

  test 'signed push syncs exactly the configured repository' do
    Repository::GitMirror.any_instance.expects(:sync!).once
    body = {repository: {ssh_url: @repository.url}}.to_json
    signature = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', 'test-secret', body)
    post @path, params: body, headers: {'CONTENT_TYPE' => 'application/json', 'X-GitHub-Event' => 'push', 'X-Hub-Signature-256' => signature}
    assert_response :accepted
  end

  test 'gitlab tag push and repository mismatch' do
    Repository::GitMirror.any_instance.expects(:sync!).once
    post @path, params: {project: {git_ssh_url: @repository.url}}, headers: {'X-Gitlab-Event' => 'Tag Push Hook', 'X-Gitlab-Token' => 'test-secret'}
    assert_response :accepted
    post @path, params: {project: {git_ssh_url: 'git@github.com:other/repo'}}, headers: {'X-Gitlab-Event' => 'Push Hook', 'X-Gitlab-Token' => 'test-secret'}
    assert_response :unprocessable_entity
  end

  test 'fetch failures are retryable service errors' do
    Repository::GitMirror.any_instance.expects(:sync!).raises(RedmineGitMirror::Error, 'SSH unavailable')
    post @path, params: {project: {git_ssh_url: @repository.url}}, headers: {'X-Gitlab-Event' => 'Push Hook', 'X-Gitlab-Token' => 'test-secret'}
    assert_response :service_unavailable
  end
end
