require 'openssl'
require 'json'

class GitMirrorController < ActionController::Base
  skip_before_action :verify_authenticity_token, raise: false
  def webhook_repository
    project = Project.find_by(identifier: params[:project_identifier])
    repository = project&.active? && Repository::GitMirror.find_by(project: project, identifier: params[:repository_identifier])
    return head(:not_found) unless repository
    secret = repository.webhook_secret.to_s
    return head(:unauthorized) if secret.empty?

    if request.headers['X-GitHub-Event'].present?
      expected = 'sha256=' + OpenSSL::HMAC.hexdigest('sha256', secret, request.raw_post)
      return head(:unauthorized) unless Rack::Utils.secure_compare(expected, request.headers['X-Hub-Signature-256'].to_s)
      return head(:ok) unless request.headers['X-GitHub-Event'] == 'push'
      payload = params[:payload].is_a?(String) ? JSON.parse(params[:payload]) : params
      remote = payload[:repository] || payload['repository'] || {}
      urls = [remote[:ssh_url] || remote['ssh_url'], remote[:clone_url] || remote['clone_url']]
    elsif request.headers['X-Gitlab-Event'].present?
      return head(:unauthorized) unless Rack::Utils.secure_compare(secret, request.headers['X-Gitlab-Token'].to_s)
      return head(:ok) unless %w[Push\ Hook Tag\ Push\ Hook Repository\ Update\ Hook].include?(request.headers['X-Gitlab-Event'])
      remote = params[:project] || {}
      urls = [remote[:git_ssh_url], remote[:git_http_url], remote[:ssh_url], remote[:http_url]]
    else
      return head(:bad_request)
    end
    return head(:unprocessable_entity) unless urls.compact.any? { |url| RedmineGitMirror::Remote.same?(repository.url, url) }
    repository.sync!
    head(:accepted)
  rescue JSON::ParserError
    head(:bad_request)
  rescue RedmineGitMirror::Error => error
    Rails.logger.warn("Git Mirror webhook: #{error.message}")
    head(:service_unavailable)
  end
end
