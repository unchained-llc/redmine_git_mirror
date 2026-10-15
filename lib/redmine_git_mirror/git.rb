require 'open3'
require 'fileutils'

module RedmineGitMirror
  module Git
    class << self
      def fetch(path, url, key)
        FileUtils.mkdir_p(path, mode: 0700)
        File.open(File.join(path, '.mirror.lock'), File::RDWR | File::CREAT, 0600) do |lock|
          lock.flock(File::LOCK_EX)
          unless File.file?(File.join(path, 'HEAD'))
            run(['init', '--bare', path], key)
            run(['--git-dir', path, 'remote', 'add', 'origin', url], key)
          end
          actual = run(['--git-dir', path, 'config', '--get', 'remote.origin.url'], key).strip
          raise Error, 'The mirror remote does not match the repository' unless Remote.same?(actual, url)
          run(['--git-dir', path, 'fetch', '--prune', 'origin', '+refs/heads/*:refs/heads/*', '+refs/tags/*:refs/tags/*'], key)
          head = run(['ls-remote', '--symref', url, 'HEAD'], key).lines.find { |line| line.start_with?('ref: refs/heads/') }
          run(['--git-dir', path, 'symbolic-ref', 'HEAD', head.split[1]], key) if head
          yield if block_given?
        end
      end

      def unreachable_commits(path)
        run(['--git-dir', path, 'fsck', '--unreachable', '--no-reflogs', '--no-progress'], nil)
          .lines.grep(/^unreachable commit /).map { |line| line.split.last }
      end

      private

      def run(args, key)
        binary = Redmine::Configuration['scm_git_command'] || 'git'
        output, _, status = Open3.capture3({'GIT_SSH_COMMAND' => Ssh.command(key), 'GIT_TERMINAL_PROMPT' => '0'}, binary, *args)
        # Do not echo remote output or credential-bearing URLs into error pages.
        raise Error, "Git #{args.include?('fetch') ? 'fetch' : args.first} failed (exit #{status.exitstatus}). Check the Deploy Key and SSH access." unless status.success?
        output
      end
    end
  end
end
