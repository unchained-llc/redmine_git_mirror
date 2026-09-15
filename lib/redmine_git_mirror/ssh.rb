
require 'etc'

require 'shellwords'

module RedmineGitMirror
  module Ssh
    class << self
      def ensure_host_known(host)
        return unless host

        known_hosts = known_hosts_file

        o, status = Open3.capture2("ssh-keygen", "-F", host, "-f", known_hosts)
        if status.success?
          return if o.match /found/
        else
          # ssh-keygen fail if known_hosts file is not exists just log and continue
          puts "ssh-keygen exited with non-zero status: #{status}"
        end

        FileUtils.mkdir_p File.dirname(known_hosts), :mode => 0700

        o, status = Open3.capture2("ssh-keyscan", host)
        unless status.success?
          puts "ssh-keyscan exited with non-zero status: #{status}"
          return
        end

        puts "Adding #{host} to #{known_hosts}"
        File.open(known_hosts, 'a', 0600) do |file|
          file.puts o
        end
      end

      def command(key_path = nil)
        command = ['ssh', '-o', "UserKnownHostsFile=#{Shellwords.escape(known_hosts_file)}"]
        if key_path && !key_path.to_s.strip.empty?
          command << '-o' << 'IdentitiesOnly=yes' << '-i' << Shellwords.escape(key_path.to_s.strip)
        end
        command.join(' ')
      end

      def generate_key(name)
        safe_name = name.to_s.downcase.gsub(/[^a-z0-9._-]+/, '_').sub(/\A[._-]+/, '')
        safe_name = 'repository' if safe_name.empty?
        directory = File.join(ssh_home, '.ssh', 'gitmirror')
        FileUtils.mkdir_p(directory, mode: 0700)

        path = File.join(directory, safe_name)
        path = File.join(directory, "#{safe_name}_#{Time.now.strftime('%Y%m%d%H%M%S')}") if File.exist?(path) || File.exist?(path + '.pub')

        _, stderr, status = Open3.capture3(
          'ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', path,
          '-C', "redmine-git-mirror-#{safe_name}"
        )
        return nil, stderr.to_s.strip unless status.success?

        File.chmod(0600, path)
        File.chmod(0644, path + '.pub')
        [path, File.read(path + '.pub').strip]
      end

      private def known_hosts_file
        File.join(ssh_home, '.ssh', 'known_hosts')
      end

      private def ssh_home
        home = ENV['HOME'].to_s
        home = Etc.getpwuid(Process.uid).dir if home.empty? || home == '/'
        home
      end
    end
  end
end
