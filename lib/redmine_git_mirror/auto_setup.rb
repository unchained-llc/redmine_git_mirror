require 'digest'
require 'securerandom'

module RedmineGitMirror
  module AutoSetup
    def self.prepare(repository)
      provider = Provider.new(repository.url)
      url = provider.ssh_url
      identity = [repository.project.identifier, repository.identifier, provider.kind, provider.path].join(':')
      path, public_key = if repository.ssh_key_path.to_s.empty?
        Ssh.automation_key(Digest::SHA256.hexdigest(identity))
      else
        [repository.ssh_key_path, Ssh.public_key(repository.ssh_key_path)]
      end
      repository.ssh_key_path = path
      repository.webhook_secret = SecureRandom.hex(32) if repository.webhook_secret.to_s.empty?
      provider.ensure_key(public_key, "Redmine #{repository.project.identifier}/#{repository.identifier}")
      repository.url = url
      Git.fetch(repository.root_url, url, path)
    end

    def self.webhook(repository)
      url = Settings.webhook_url(repository.project.identifier, repository.identifier)
      Provider.new(repository.url).ensure_webhook(
        url, repository.webhook_secret, previous_url: (repository.extra_info || {})['git_mirror_webhook_url']
      )
      url
    end
  end
end
