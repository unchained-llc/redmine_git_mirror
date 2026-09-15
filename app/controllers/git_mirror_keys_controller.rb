require 'securerandom'

class GitMirrorKeysController < ApplicationController
  # The request is sent from the Redmine repository form with its CSRF token.

  def generate
    project = Project.find_by(identifier: params[:project_identifier].to_s)
    unless project&.active? && User.current.logged? && User.current.allowed_to?(:manage_repository, project)
      render json: {error: 'not authorized'}, status: :forbidden
      return
    end

    repository_identifier = params[:repository_identifier].to_s.strip
    if repository_identifier.empty?
      render json: {error: 'repository identifier is required'}, status: :unprocessable_entity
      return
    end

    name = [project.identifier, repository_identifier].join('_')
    path, public_key_or_error = RedmineGitMirror::Ssh.generate_key(name)
    if path.nil?
      render json: {error: public_key_or_error}, status: :unprocessable_entity
    else
      render json: {path: path, public_key: public_key_or_error}
    end
  end

  def generate_secret
    project = Project.find_by(identifier: params[:project_identifier].to_s)
    unless project&.active? && User.current.logged? && User.current.allowed_to?(:manage_repository, project)
      render json: {error: 'not authorized'}, status: :forbidden
      return
    end

    render json: {secret: SecureRandom.hex(32)}
  end
end
