require 'redmine'

%w[http remote settings oauth provider ssh git auto_setup hooks].each do |name|
  require_dependency File.join(__dir__, 'lib/redmine_git_mirror', name)
end

Redmine::Scm::Base.add 'GitMirror'
Redmine::Plugin.register :redmine_git_mirror do
  name 'Git Mirror'
  author 'Sergey Linnik / UNCHAINED'
  description 'Select a GitHub or GitLab repository to mirror in Redmine'
  version '2.0.0'
  url 'https://github.com/linniksa/redmine_git_mirror'
  requires_redmine version_or_higher: '5.0'
  settings default: RedmineGitMirror::Settings::DEFAULT, partial: 'git_mirror/settings'
end

Rails.application.config.filter_parameters |= %i[github_api_token gitlab_api_token webhook_secret access_token refresh_token client_secret code]
# Redmine already runs this initializer in to_prepare: apply patches now.
require_dependency 'settings_controller'
require_dependency 'repositories_helper'
require_dependency 'repositories_controller'
%w[settings_controller repositories_controller repositories_helper].each do |name|
  require_dependency File.join(__dir__, 'lib/redmine_git_mirror/patches', "#{name}_patch")
end
SettingsController.prepend(RedmineGitMirror::Patches::SettingsControllerPatch) unless SettingsController.ancestors.include?(RedmineGitMirror::Patches::SettingsControllerPatch)
RepositoriesController.prepend(RedmineGitMirror::Patches::RepositoriesControllerPatch) unless RepositoriesController.ancestors.include?(RedmineGitMirror::Patches::RepositoriesControllerPatch)
RepositoriesHelper.include(RedmineGitMirror::Patches::RepositoriesHelperPatch) unless RepositoriesHelper.ancestors.include?(RedmineGitMirror::Patches::RepositoriesHelperPatch)
