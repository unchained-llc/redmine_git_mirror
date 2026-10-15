module RedmineGitMirror
  module Patches
    module SettingsControllerPatch
      def plugin
        return super unless params[:id] == 'redmine_git_mirror' && request.post?
        # Lock together with OAuth token refresh so a form save cannot discard
        # a freshly rotated refresh token. The core action performs the save.
        Setting.transaction do
          row = Setting.find_by(name: 'plugin_redmine_git_mirror')
          row.lock! if row
          Setting.clear_cache
          prepare_git_mirror_settings
          super
        end
      end

      private

      def prepare_git_mirror_settings
        saved = (Setting.plugin_redmine_git_mirror || {}).stringify_keys
        submitted = params[:settings] || ActionController::Parameters.new
        values = saved.slice('custom_path', 'gitlab_url').merge(submitted.permit(:custom_path, :gitlab_url).to_h)
        values['gitlab_url'] ||= 'https://gitlab.com'
        Settings::PROVIDERS.each do |provider|
          token = submitted["#{provider}_api_token"].to_s.strip
          host_changed = provider == 'gitlab' && values['gitlab_url'].to_s.sub(%r{/+\z}, '') != saved.fetch('gitlab_url', 'https://gitlab.com').to_s.sub(%r{/+\z}, '')
          values["#{provider}_api_token"] = token.empty? ? (host_changed ? '' : saved["#{provider}_api_token"].to_s) : Settings.encrypt(token)
          values["#{provider}_oauth"] = saved["#{provider}_oauth"] if token.empty? && !host_changed
        end
        params[:settings] = ActionController::Parameters.new(values.compact)
      end
    end
  end
end
