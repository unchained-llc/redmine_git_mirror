require File.expand_path('../../test_helper', __FILE__)

class AutoSetupIntegrationTest < Redmine::IntegrationTest
  fixtures :users, :projects, :enabled_modules

  setup do
    Setting.enabled_scm = %w[GitMirror]
    @repository = Repository::GitMirror.new(project: Project.find(1), identifier: 'automatic-mirror', url: 'https://github.com/example/private-repo')
    User.current = User.find(1)
    RedmineGitMirror::Settings.stubs(:connected?).returns(true)
  end

  teardown { User.current = nil }

  test 'validation makes no provider writes and ordinary managers cannot create' do
    RedmineGitMirror::AutoSetup.expects(:prepare).never
    User.current = User.find(2)
    assert_not @repository.save
    assert_includes @repository.errors[:base], I18n.t(:git_mirror_admin_required)
  end

  test 'initial fetch failure does not persist the repository' do
    RedmineGitMirror::AutoSetup.expects(:prepare).raises(RedmineGitMirror::Error, 'SSH unavailable')
    assert_not @repository.save
    assert @repository.new_record?
    assert_match /SSH unavailable/, @repository.errors[:base].join
  end

  test 'provider setup does not run during validation' do
    RedmineGitMirror::AutoSetup.expects(:prepare).never
    assert @repository.valid?
  end

  test 'internal credentials cannot be mass assigned' do
    @repository.safe_attributes = {'ssh_key_path' => '/tmp/untrusted', 'webhook_secret' => 'untrusted', 'root_url' => '/tmp/untrusted'}
    assert_nil @repository.ssh_key_path
    assert_nil @repository.webhook_secret
    assert_nil @repository.root_url
  end

  test 'first boot installs the settings patch' do
    assert_includes SettingsController.ancestors, RedmineGitMirror::Patches::SettingsControllerPatch
  end

  test 'settings encrypt PATs and preserve them on blank input' do
    log_user('admin', 'admin')
    post '/settings/plugin/redmine_git_mirror', params: {settings: {gitlab_api_token: 'test-token', gitlab_url: 'https://gitlab.com'}}
    assert_response :redirect
    ciphertext = Setting.plugin_redmine_git_mirror['gitlab_api_token']
    refute_equal 'test-token', ciphertext
    assert_equal 'test-token', RedmineGitMirror::Settings.api_token('gitlab')
    post '/settings/plugin/redmine_git_mirror', params: {settings: {gitlab_api_token: ''}}
    assert_response :redirect
    assert_equal ciphertext, Setting.plugin_redmine_git_mirror['gitlab_api_token']
  end

  test 'changing the GitLab host clears its saved credentials' do
    log_user('admin', 'admin')
    with_settings plugin_redmine_git_mirror: {'gitlab_url' => 'https://old.example', 'gitlab_api_token' => 'old-ciphertext', 'gitlab_oauth' => 'old-oauth'} do
      post '/settings/plugin/redmine_git_mirror', params: {settings: {gitlab_url: 'https://new.example'}}
      assert_response :redirect
      assert_equal '', Setting.plugin_redmine_git_mirror['gitlab_api_token']
      assert_nil Setting.plugin_redmine_git_mirror['gitlab_oauth']
    end
  end

  test 'repository catalog is admin only' do
    log_user('jsmith', 'jsmith')
    RedmineGitMirror::Provider.expects(:new).never
    get '/git_mirror/repositories/github'
    assert_response :forbidden
  end

  test 'repository catalog returns names without credentials' do
    log_user('admin', 'admin')
    provider = mock
    provider.expects(:repositories).returns([{name: 'team/repo', url: 'https://github.com/team/repo', available: true}])
    RedmineGitMirror::Provider.expects(:new).with('github').returns(provider)
    get '/git_mirror/repositories/github'
    assert_response :success
    assert_equal 'team/repo', JSON.parse(response.body).first['name']
  end

  test 'removed manual key endpoints do not exist' do
    %w[/sys/git_mirror/ssh_key /sys/git_mirror/webhook_secret].each do |path|
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(path, method: :post) }
    end
  end

  test 'remote cleanup failure keeps the repository' do
    RedmineGitMirror::AutoSetup.stubs(:prepare)
    RedmineGitMirror::AutoSetup.stubs(:webhook)
    Repository::GitMirror.any_instance.stubs(:fetch_changesets)
    assert @repository.save
    provider = mock
    provider.expects(:remove_connection).raises(RedmineGitMirror::Error, 'HTTP 403')
    RedmineGitMirror::Provider.stubs(:new).returns(provider)
    assert_not @repository.destroy
    assert Repository::GitMirror.exists?(@repository.id)
    assert_match /HTTP 403/, @repository.errors[:base].join
  end
end
