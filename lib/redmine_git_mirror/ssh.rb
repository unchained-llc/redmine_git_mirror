require 'etc'
require 'fileutils'
require 'open3'
require 'shellwords'

module RedmineGitMirror
  module Ssh
    class << self
      def automation_key(identity)
        directory = File.join(ssh_home, '.ssh', 'gitmirror')
        FileUtils.mkdir_p(directory, mode: 0700)
        path = File.join(directory, "auto_#{identity}")
        File.open(path + '.lock', File::RDWR | File::CREAT, 0600) do |lock|
          lock.flock(File::LOCK_EX)
          unless File.exist?(path)
            _, stderr, status = Open3.capture3('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', path, '-C', 'redmine-git-mirror')
            raise Error, "SSH key generation failed: #{stderr.to_s.lines.first}" unless status.success?
            File.chmod(0600, path)
          end
          public_key(path).then { |key| [path, key] }
        end
      end

      def public_key(path)
        output, _, status = Open3.capture3('ssh-keygen', '-y', '-f', path)
        raise Error, 'Cannot read the SSH key' unless status.success?
        output.strip
      end

      def command(path)
        directory = File.join(ssh_home, '.ssh')
        FileUtils.mkdir_p(directory, mode: 0700)
        args = ['ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=#{File.join(directory, 'known_hosts')}"]
        args += ['-o', 'IdentitiesOnly=yes', '-i', path] unless path.to_s.empty?
        Shellwords.join(args)
      end

      def remove_key(path)
        directory = File.join(ssh_home, '.ssh', 'gitmirror')
        return unless File.expand_path(File.dirname(path.to_s)) == directory
        return unless File.basename(path).match?(/\Aauto_[a-f0-9]{64}\z/)
        return if File.symlink?(path)
        [path, path + '.pub', path + '.lock'].each { |file| FileUtils.rm_f(file) }
      end

      private

      def ssh_home
        value = ENV['HOME'].to_s
        value.empty? || value == '/' ? Etc.getpwuid(Process.uid).dir : value
      end
    end
  end
end
