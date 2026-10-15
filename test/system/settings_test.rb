require File.expand_path('../../test_helper.rb', __FILE__)

class GitMirrorSettingsTest < GitMirrorUITestCase
  fixtures :users

  def test_minimal_settings_preserve_existing_connection
    log_user('admin', 'admin')
    visit '/settings/plugin/redmine_git_mirror'
    assert page.has_field?('Repositories Path')
    assert page.has_no_field?('Allow users to change URL')
    fill_in 'Repositories Path', with: '/tmp/redmine-test-mirrors'
    click_button 'Apply', exact: true
    assert page.has_content?('Successful update')
    assert_equal '/tmp/redmine-test-mirrors', RedmineGitMirror::Settings.path
  end
end
