class GitMirrorConnectionsController < ApplicationController
  before_action :require_admin

  def repositories
    render json: RedmineGitMirror::Provider.new(params[:provider].to_s).repositories
  rescue RedmineGitMirror::Error => error
    render json: {error: error.message}, status: :unprocessable_entity
  end

  def authorize
    url, flow = RedmineGitMirror::Oauth.begin_authorization(params[:provider].to_s, User.current.id)
    session[:git_mirror_oauth] = flow
    redirect_to url, allow_other_host: true
  rescue RedmineGitMirror::Error => error
    redirect_to plugin_settings_path('redmine_git_mirror'), alert: error.message
  end

  def callback
    flow = session.delete(:git_mirror_oauth)
    RedmineGitMirror::Oauth.finish_authorization(params[:provider].to_s, flow, params[:state], params[:code], User.current.id)
    redirect_to plugin_settings_path('redmine_git_mirror'), notice: l(:git_mirror_connected)
  rescue RedmineGitMirror::Error => error
    redirect_to plugin_settings_path('redmine_git_mirror'), alert: error.message
  end

  def disconnect
    provider = params[:provider].to_s
    return head(:bad_request) unless RedmineGitMirror::Settings::PROVIDERS.include?(provider)
    RedmineGitMirror::Settings.update do |values|
      values.delete("#{provider}_oauth")
      values["#{provider}_api_token"] = ''
    end
    redirect_to plugin_settings_path('redmine_git_mirror')
  end

  def retry_setup
    repository = Repository::GitMirror.find(params[:id])
    if repository.retry_setup!
      flash[:notice] = l(:git_mirror_setup_complete)
    else
      flash[:error] = repository.setup_error
    end
    redirect_to edit_repository_path(repository)
  rescue RedmineGitMirror::Error, ActiveRecord::RecordInvalid => error
    redirect_to edit_repository_path(repository), alert: error.message
  end
end
