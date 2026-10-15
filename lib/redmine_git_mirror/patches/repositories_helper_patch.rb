module RedmineGitMirror
  module Patches
    module RepositoriesHelperPatch
      def git_mirror_field_tags(form, repository)
        render partial: 'git_mirror/repository', locals: {form: form, repository: repository}
      end
    end
  end
end
