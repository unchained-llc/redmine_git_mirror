require 'securerandom'

class Repository::GitMirror < Repository::Git
  before_validation :prepare_attributes, on: :create
  validate :validate_creation, on: :create
  validate :validate_location, on: :update
  before_create :provision_mirror
  after_create_commit :complete_setup
  before_destroy :remove_remote_connection, prepend: true
  after_destroy_commit :remove_local_files

  scope :active, -> { joins(:project).merge(Project.active) }

  # Credentials and on-disk locations are always managed internally.
  def safe_attribute_names(user = nil)
    super - %w[ssh_key_path webhook_secret root_url] - (new_record? ? [] : ['url'])
  end

  def self.scm_name
    'Git Mirror'
  end

  def self.human_attribute_name(attribute, *args)
    Repository.human_attribute_name(attribute, *args)
  end

  def self.fetch
    active.find_each(&:fetch)
  end

  def home_url
    remote = RedmineGitMirror::Remote.new(url)
    origin = remote.host == 'github.com' ? 'https://github.com' : RedmineGitMirror::Settings.gitlab_url
    prefix = URI.parse(origin).path.sub(%r{\A/}, '') + '/'
    path = prefix == '/' ? remote.path : remote.path.delete_prefix(prefix)
    "#{origin}/#{path}"
  rescue RedmineGitMirror::Error, ArgumentError
    nil
  end

  def setup_error
    (extra_info || {})['git_mirror_error']
  end

  # Redmine's automatic view-time import must not trigger a network fetch.
  def fetch_changesets(force = false)
    super() if force
  end

  def sync!
    RedmineGitMirror::Git.fetch(root_url, url, ssh_key_path) do
      commits = RedmineGitMirror::Git.unreachable_commits(root_url)
      unless commits.empty?
        heads = (extra_info || {})['heads']
        merge_extra_info('heads' => heads - commits) if heads.is_a?(Array)
        Changeset.where(repository: self, revision: commits).destroy_all
      end
      fetch_changesets(true)
    end
    true
  end

  def fetch
    sync!
  rescue RedmineGitMirror::Error => error
    Rails.logger.warn("Git Mirror #{id}: #{error.message}")
    false
  end

  def retry_setup!
    RedmineGitMirror::AutoSetup.prepare(self)
    save!
    complete_setup
  end

  private

  def prepare_attributes
    remote = RedmineGitMirror::Remote.new(url)
    if identifier.to_s.empty?
      value = remote.path.split('/').last.downcase.gsub(/[^a-z0-9_-]+/, '-')
      value = "repo-#{value}" unless value.match?(/\A[a-z]/)
      self.identifier = value[0, Repository::IDENTIFIER_MAX_LENGTH]
    end
    self.root_url = File.join(RedmineGitMirror::Settings.path, SecureRandom.uuid) if root_url.to_s.empty?
  rescue ArgumentError
    errors.add(:url, :invalid)
  end

  def validate_creation
    errors.add(:base, I18n.t(:git_mirror_admin_required)) unless User.current.admin?
    errors.add(:url, :blank) if url.to_s.empty?
    return unless errors.empty?
    RedmineGitMirror::Provider.new(url)
    if self.class.where(project_id: project_id).any? { |other| RedmineGitMirror::Remote.same?(other.url, url) }
      errors.add(:url, I18n.t(:git_mirror_already_added))
    end
  rescue RedmineGitMirror::Error => error
    errors.add(:base, error.message)
  end

  def validate_location
    errors.add(:root_url, :invalid) if root_url_changed?
    if url_changed? && !RedmineGitMirror::Remote.same?(url_was, url)
      errors.add(:url, :invalid)
    end
  end

  def provision_mirror
    RedmineGitMirror::AutoSetup.prepare(self)
  rescue RedmineGitMirror::Error, SystemCallError, IOError => error
    errors.add(:base, I18n.t(:git_mirror_setup_failed, message: error.message))
    throw :abort
  end

  def complete_setup
    # The row and secret are committed before the provider sends its first ping.
    fetch_changesets(true)
    callback = RedmineGitMirror::AutoSetup.webhook(self)
    store_setup_error(nil, webhook_url: callback)
    true
  rescue RedmineGitMirror::Error => error
    store_setup_error(error.message)
    false
  rescue StandardError => error
    Rails.logger.error("Git Mirror setup #{id}: #{error.class}")
    store_setup_error(I18n.t(:git_mirror_import_failed))
    false
  end

  def store_setup_error(message, webhook_url: nil)
    info = (extra_info || {}).merge('git_mirror_error' => message)
    info['git_mirror_webhook_url'] = webhook_url if webhook_url
    update_column(:extra_info, info)
  end

  def remove_mirror
    path = root_url.to_s
    return if path.empty? || path == '/' || path.length <= 15 || File.symlink?(path)
    return unless File.file?(File.join(path, 'HEAD')) && File.directory?(File.join(path, 'objects'))
    FileUtils.rm_rf(path)
  end

  def remove_remote_connection
    shared_key = ssh_key_path.present? && self.class.where(ssh_key_path: ssh_key_path).where.not(id: id).exists?
    key = ssh_key_path.present? && !shared_key ? RedmineGitMirror::Ssh.public_key(ssh_key_path) : nil
    RedmineGitMirror::Provider.new(url).remove_connection(
      (extra_info || {})['git_mirror_webhook_url'] || RedmineGitMirror::Settings.webhook_url(project.identifier, identifier),
      public_key: key, title: "Redmine #{project.identifier}/#{identifier}"
    )
  rescue RedmineGitMirror::Error, SystemCallError, IOError => error
    errors.add(:base, I18n.t(:git_mirror_delete_failed, message: error.message))
    throw :abort
  end

  def remove_local_files
    remove_mirror
    if ssh_key_path.present? && !self.class.where(ssh_key_path: ssh_key_path).exists?
      RedmineGitMirror::Ssh.remove_key(ssh_key_path)
    end
  rescue SystemCallError, IOError => error
    Rails.logger.error("Git Mirror #{id}: local cleanup failed (#{error.class})")
  end
end
