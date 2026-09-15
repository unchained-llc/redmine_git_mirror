
match 'sys/git_mirror/webhook/:project_identifier/:repository_identifier', to: 'git_mirror#webhook_repository', via: [:post]
match 'sys/git_mirror/ssh_key', to: 'git_mirror_keys#generate', via: [:post]
match 'sys/git_mirror/webhook_secret', to: 'git_mirror_keys#generate_secret', via: [:post]
