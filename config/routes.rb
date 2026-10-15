post 'sys/git_mirror/webhook/:project_identifier/:repository_identifier', to: 'git_mirror#webhook_repository'
get 'git_mirror/repositories/:provider', to: 'git_mirror_connections#repositories', constraints: {provider: /github|gitlab/}, as: :git_mirror_catalog
post 'git_mirror/oauth/:provider', to: 'git_mirror_connections#authorize', constraints: {provider: /github|gitlab/}, as: :git_mirror_authorize
get 'git_mirror/oauth/:provider/callback', to: 'git_mirror_connections#callback', constraints: {provider: /github|gitlab/}, as: :git_mirror_callback
post 'git_mirror/disconnect/:provider', to: 'git_mirror_connections#disconnect', constraints: {provider: /github|gitlab/}, as: :git_mirror_disconnect
post 'git_mirror/repositories/:id/retry', to: 'git_mirror_connections#retry_setup', as: :git_mirror_retry
