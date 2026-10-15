module RedmineGitMirror
  module Patches
    module RepositoriesControllerPatch
      def create
        return super unless @repository.is_a?(Repository::GitMirror)
        if @repository.save
          if @repository.setup_error.present?
            flash[:error] = l(:git_mirror_setup_pending, message: @repository.setup_error)
            redirect_to edit_repository_path(@repository)
          else
            flash[:notice] = l(:git_mirror_setup_complete)
            redirect_to settings_project_path(@project, tab: 'repositories')
          end
        else
          no_store
          render action: 'new'
        end
      end

      def destroy
        return super unless @repository.is_a?(Repository::GitMirror)
        if request.delete?
          if @repository.destroy
            flash[:notice] = l(:git_mirror_deleted)
          else
            flash[:error] = ERB::Util.html_escape(@repository.errors.full_messages.join('\n'))
          end
        end
        redirect_to settings_project_path(@project, tab: 'repositories')
      end
    end
  end
end
