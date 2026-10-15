require File.expand_path('../../test_helper.rb', __FILE__)

class GitMirrorProjectTest < GitMirrorUITestCase
  fixtures :users, :projects, :enabled_modules

  setup { Setting.enabled_scm = %w[GitMirror] }

  def test_unconnected_repository_form_has_no_manual_credentials
    log_user('admin', 'admin')
    visit '/projects/ecookbook/repositories/new'
    select 'Git Mirror', from: 'Version control system'
    assert page.has_content?('Connect to GitHub or GitLab')
    assert page.has_no_button?('Generate SSH key')
    assert page.has_no_field?('repository_ssh_key_path')
  end
end
