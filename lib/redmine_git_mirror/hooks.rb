module RedmineGitMirror
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_repositories_navigation, partial: 'repositories/git_mirror_navigation'

    def view_layouts_base_html_head(_context = {})
      stylesheet_link_tag('redmine_git_mirror', plugin: 'redmine_git_mirror') +
        javascript_include_tag('redmine_git_mirror', plugin: 'redmine_git_mirror', defer: true)
    end
  end
end
