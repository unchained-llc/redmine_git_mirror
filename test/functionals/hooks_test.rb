require File.expand_path('../../test_helper', __FILE__)

class HooksTest < Redmine::IntegrationTest
  fixtures :users, :projects, :enabled_modules

  setup do
    Setting.enabled_scm = %w(GitMirror)
    Repository.delete_all

    @repository = Repository::GitMirror.new
    @repository.url = 'https://github.com/linniksa/redmine_git_mirror.git'
    @repository.project = Project.find(1)
    @repository.webhook_secret = 'test-secret'
    @repository.save!
  end

  teardown do
    Repository.delete_all
  end

  test 'repository webhook rejects an invalid secret' do
    post '/sys/git_mirror/webhook/ecookbook/' + @repository.identifier,
         :params => {
           'repository' => {
             'clone_url' => @repository.url,
           }
         }.to_json,
         :headers => {
           'CONTENT_TYPE' => 'application/json',
           'X-GitHub-Event' => 'push',
           'X-Hub-Signature-256' => 'sha256=invalid',
         }

    assert_response 401
  end

  test 'removed general hook endpoint does not exist' do
    get '/sys/git_mirror/fetch', :params => { 'url' => @repository.url }

    assert_response 404
  end
end
