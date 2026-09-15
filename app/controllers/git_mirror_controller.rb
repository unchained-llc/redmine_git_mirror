
class GitMirrorController < ActionController::Base

  # Requests to this controller don't contain CSRF tokens
  skip_before_action :verify_authenticity_token

  # Receive either GitLab or GitHub events for one repository.
  def webhook_repository
    repository = repository_from_webhook_path
    head 404 and return unless repository

    if request.headers['X-Gitlab-Event'].present? || params[:event_name].present?
      head 401 and return unless repository.webhook_secret.present? && verify_gitlab_signature(repository.webhook_secret)
      head 200 and return unless request.post? && %w[push repository_update].include?(params[:event_name].to_s)
      head 422 and return unless params[:project]
      head fetch_webhook_repository(repository) ? 202 : 404
    elsif request.headers['X-GitHub-Event'].present?
      head 401 and return unless repository.webhook_secret.present? && verify_github_signature(repository.webhook_secret)
      event = request.headers['X-GitHub-Event']
      head 200 and return unless request.post? && event == 'push'

      payload = params[:payload]
      payload = JSON.parse(payload, symbolize_names: true) if payload && request.content_type != 'application/json'
      repository_data = (payload || params)[:repository]
      head 422 and return unless repository_data
      head fetch_webhook_repository(repository, repository_data) ? 202 : 404
    else
      head 400
    end
  end

  private def repository_from_webhook_path
    project = Project.find_by(identifier: params[:project_identifier].to_s)
    return nil unless project&.active?

    Repository::GitMirror.active.where(project: project, identifier: params[:repository_identifier].to_s).first
  end

  private def fetch_webhook_repository(repository, payload_repository = nil)
    if payload_repository
      urls = [:ssh_url, :clone_url, :git_url].filter_map { |key| payload_repository[key].presence }
      return false if urls.empty? || !RedmineGitMirror::URL.parse(repository.url).vary.any? { |url| urls.include?(url) }
    end

    repository.fetch
    true
  rescue StandardError
    false
  end

  private def verify_gitlab_signature(repository_secret = nil)
    expectedToken = repository_secret.to_s
    return true unless expectedToken.present?

    token = request.headers["X-Gitlab-Token"]
    return expectedToken == token
  end

  private def verify_github_signature(repository_secret = nil)
    secretKey = repository_secret.to_s
    return true unless secretKey.present?

    signature = request.headers["X-Hub-Signature-256"]
    return false unless signature.present?

    digest = OpenSSL::Digest.new("sha256")
    expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(digest, secretKey, request.raw_post)
    return Rack::Utils.secure_compare(expected_signature, signature)
  end
end
