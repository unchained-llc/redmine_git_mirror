# Run with the target Redmine bundle; this does not boot Rails or access its DB.
require 'zeitwerk'
module Redmine
  module Hook
    class ViewListener
      def self.render_on(*); end
    end
  end
end
loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path('../../lib', __dir__))
loader.setup
loader.eager_load
abort 'Missing Oauth' unless defined?(RedmineGitMirror::Oauth)
puts 'Zeitwerk eager load OK'
