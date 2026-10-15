# Redmine Git Mirror

Select a GitHub or GitLab repository and mirror it in Redmine. New repositories
always use automatic setup: read-only SSH Deploy Key, initial fetch, changeset
import and a signed push/tag webhook. There is no manual-key or webhook editor.

## Install

Install this directory as `plugins/redmine_git_mirror`, run `bundle install` and
`bundle exec rake redmine:plugins:migrate RAILS_ENV=production`, then restart
Redmine. Enable **Git Mirror** under **Administration → Settings → Repositories**.
Redmine 5 or later, Git, OpenSSH and outbound HTTPS/SSH access are required.

## Connect

Under **Administration → Plugins → Git Mirror → Configure**, connect GitHub or
GitLab. Connections are shared and can only be used by Redmine administrators.
Repository managers can browse existing mirrors but cannot use shared credentials
to create or reconfigure them.

### OAuth

Register an OAuth application once with each provider. Configure the following
server environment variables and restart Redmine:

| Provider | Variables | Callback URL |
| --- | --- | --- |
| GitHub.com | `GIT_MIRROR_GITHUB_CLIENT_ID`, `GIT_MIRROR_GITHUB_CLIENT_SECRET` | `https://REDMINE/git_mirror/oauth/github/callback` |
| GitLab | `GIT_MIRROR_GITLAB_CLIENT_ID`, `GIT_MIRROR_GITLAB_CLIENT_SECRET` | `https://REDMINE/git_mirror/oauth/gitlab/callback` |

Use Redmine's configured hostname, protocol and installation subpath in callback
URLs. GitLab applications must allow the `api` scope and use a confidential client.
GitHub OAuth requests `repo` scope to manage Deploy Keys for private repositories;
this scope also permits repository writes. GitHub organization approval may be
required. Tokens are acquired by the **Connect** button; users do not copy them.
The authorization flow uses session-bound, expiring state and PKCE S256. Expiring
access tokens refresh automatically; rotated refresh tokens are stored under a
DB lock. Client secrets remain in the server environment.

OAuth setup references: [GitHub](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps),
[GitLab](https://docs.gitlab.com/api/oauth2/).

### Existing PAT connections

Existing saved PATs continue to work. Alternatively, expand **Connect with a PAT**:

- GitHub: fine-grained PAT with **Administration: Read and write** and
  **Webhooks: Read and write** for the selected repositories.
- GitLab: token with `api` scope and Maintainer or higher access; configure its
  HTTPS instance URL, including an installation subpath if needed.

Leave token inputs blank to keep the connection. A new PAT replaces OAuth for
that provider. Changing the GitLab instance clears its old credentials. Disconnect
removes locally saved credentials; it does not revoke the provider's OAuth grant,
Deploy Keys or webhooks. Tokens are encrypted with the Rails application key;
keep that key stable across deployments. Provider-created Deploy Keys may be
removed when the PAT/OAuth grant that created them is revoked.

## Create a mirror

Open **Project → Settings → Repositories → New repository**, select **Git Mirror**,
choose a connection, search the repository list, select a repository and create.
The identifier is filled automatically and can be adjusted before creation.
GitHub entries without administration access or archived entries cannot be selected;
GitLab lists member projects with Maintainer or higher access. A token may still
lack the API permissions needed for setup even if its user administers the repo.

The plugin fetches first, commits the Redmine repository and its secret, then
registers the webhook. The provider's first ping therefore sees the committed row.
If the initial fetch fails, creation fails. If webhook registration or changeset
import fails after commit, the repository remains saved with a visible error and
**Retry automatic setup** action. Retrying reuses its key and webhook. Concurrent
Git fetches on the same mirror are serialized using a file lock.

## Storage and updates

The only mirror behavior setting is **Repositories Path**. The default is
`files/git_mirrors` under Redmine, outside the plugin code. It applies to new
mirrors only; existing `root_url`, `ssh_key_path`, secrets and encrypted PATs are
preserved. Old behavior toggles are ignored and removed on the next settings save.
Do not use code deployment to remove existing ignored mirrors in the old
plugin-local `repos/` directory.

Pushes/tags sync through the repository-scoped webhook. An optional cron fallback
is still available: `bundle exec rails runner -e production 'Repository::GitMirror.fetch'`.
Deleting a repository removes the exact callback URL and its dedicated Deploy Key
(matching both title and public key), then deletes the Redmine row. Its local
mirror and generated SSH key files are removed after commit. Shared or manually
managed SSH keys and unrelated provider resources are preserved. If remote cleanup
fails, deletion is aborted with a visible error so it can be retried. Keep the
connection active until mirrors have been deleted.

## Tests

- `ruby test/standalone/auto_setup_test.rb`: isolated provider/OAuth and real Git/SSH tests.
- Inside a test Redmine installation: `bundle exec ruby plugins/redmine_git_mirror/test/all.rb`.

GitHub.com and one configurable GitLab instance are supported. OAuth requires the
application registration above; this plugin does not create provider applications.
