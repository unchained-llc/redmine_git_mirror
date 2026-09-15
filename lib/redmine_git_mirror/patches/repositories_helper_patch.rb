module RedmineGitMirror
  module Patches
    module RepositoriesHelperPatch

      def git_mirror_field_tags(form, repository)
        project_identifier = repository.project&.identifier.to_s
        repository_identifier = repository.identifier.to_s
        base_url = "#{Setting.protocol}://#{Setting.host_name}"
        repository_hook_url = "#{base_url}/sys/git_mirror/webhook/#{project_identifier}/#{repository_identifier}"
        generate_key_url = "#{base_url}/sys/git_mirror/ssh_key"
        generate_secret_url = "#{base_url}/sys/git_mirror/webhook_secret"
        webhook_secret = repository.respond_to?(:webhook_secret) ? repository.webhook_secret : nil

        content_tag('p', form.text_field(
          :url,
          :size => 60,
          :required => true,
          :disabled => !repository.safe_attribute?('url'),
          ) +
          content_tag('em', l(:text_git_mirror_url_note), :class => 'info')
        ) +
        content_tag('p', content_tag('button', l(:button_git_mirror_generate_ssh_key),
          :type => 'button', :id => 'git-mirror-generate-ssh-key')) +
        content_tag('p', label_tag('git_mirror_ssh_public_key', l(:label_git_mirror_ssh_public_key)) +
          content_tag('span',
            text_area_tag('git_mirror_ssh_public_key', nil, :rows => 2, :cols => 80, :readonly => true) +
            content_tag('button', l(:button_git_mirror_copy), :type => 'button',
              :class => 'git-mirror-copy-button', 'data-copy-target' => 'git_mirror_ssh_public_key'),
            :class => 'git-mirror-field-with-copy') +
          content_tag('em', l(:text_git_mirror_ssh_public_key_note), :class => 'info')) +
        content_tag('p', form.text_field(
          :ssh_key_path,
          :size => 60,
          :placeholder => '/home/redmine/.ssh/gitmirror/<repository-key>'
        ) +
        content_tag('em', l(:text_git_mirror_ssh_key_path_note), :class => 'info')) +
        content_tag('p', text_field_tag('repository[webhook_secret]', webhook_secret,
          :id => 'repository_webhook_secret', :size => 60, :readonly => false) +
          content_tag('span',
            content_tag('button', l(:button_git_mirror_generate_webhook_secret), :type => 'button', :id => 'git-mirror-generate-webhook-secret') +
            content_tag('button', l(:button_git_mirror_copy), :type => 'button',
              :class => 'git-mirror-copy-button', 'data-copy-target' => 'repository_webhook_secret'),
            :class => 'git-mirror-field-actions') +
          content_tag('em', l(:text_git_mirror_webhook_secret_note), :class => 'info')) +
        content_tag('fieldset',
          content_tag('legend', l(:label_git_mirror_webhook_urls)) +
          content_tag('p', label_tag('git_mirror_repository_hook_url', 'GitLab / GitHub') +
            content_tag('span',
              text_field_tag('git_mirror_repository_hook_url', repository_hook_url, :size => 80, :readonly => true) +
              content_tag('button', l(:button_git_mirror_copy), :type => 'button',
                :class => 'git-mirror-copy-button', 'data-copy-target' => 'git_mirror_repository_hook_url'),
              :class => 'git-mirror-field-with-copy'))
        ) +
        javascript_tag(<<~JS)
          (() => {
            const copyText = async (value) => {
              if (navigator.clipboard && window.isSecureContext) {
                await navigator.clipboard.writeText(value);
                return;
              }
              const helper = document.createElement('textarea');
              helper.value = value;
              helper.setAttribute('readonly', '');
              helper.style.position = 'fixed';
              helper.style.opacity = '0';
              document.body.appendChild(helper);
              helper.select();
              document.execCommand('copy');
              helper.remove();
            };

            document.querySelectorAll('.git-mirror-copy-button').forEach((button) => {
              if (button.dataset.ready) return;
              button.dataset.ready = '1';
              button.addEventListener('click', async () => {
                const field = document.getElementById(button.dataset.copyTarget);
                if (!field || !field.value) return;
                const label = button.textContent;
                try {
                  await copyText(field.value);
                  button.textContent = #{l(:text_git_mirror_copied).to_json};
                  setTimeout(() => { button.textContent = label; }, 1200);
                } catch (error) {
                  alert(error.message || 'Copy failed');
                }
              });
            });

            const urlField = document.getElementById('repository_url');
            const identifierField = document.getElementById('repository_identifier');
            const projectIdentifier = #{project_identifier.to_json};
            const baseUrl = #{base_url.to_json};

            if (urlField && identifierField && !urlField.dataset.gitMirrorReady) {
              urlField.dataset.gitMirrorReady = '1';
              identifierField.dataset.gitMirrorAuto = identifierField.value ? '0' : '1';

              const updateFromUrl = () => {
                const value = urlField.value.trim().replace(/\\/$/, '');
                const match = value.match(/(?:^|[/:])([^/:]+?)(?:\\.git)?$/i);
                if (match && (!identifierField.value || identifierField.dataset.gitMirrorAuto === '1')) {
                  let identifier = match[1].toLowerCase().replace(/[^a-z0-9_-]+/g, '-');
                  if (!/^[a-z]/.test(identifier)) identifier = `repo-${identifier}`;
                  identifier = identifier.replace(/-+/g, '-').replace(/^-|-$/g, '');
                  identifierField.value = identifier;
                  identifierField.dataset.gitMirrorAuto = '1';
                }
                updateWebhookUrls();
              };

              const updateWebhookUrls = () => {
                const identifier = identifierField.value.trim();
                const webhook = document.getElementById('git_mirror_repository_hook_url');
                if (webhook) webhook.value = `${baseUrl}/sys/git_mirror/webhook/${projectIdentifier}/${identifier}`;
              };

              identifierField.addEventListener('input', () => {
                identifierField.dataset.gitMirrorAuto = '0';
                updateWebhookUrls();
              });
              urlField.addEventListener('input', updateFromUrl);

              const identifierParent = identifierField.closest('p');
              const urlParent = urlField.closest('p');
              if (identifierParent && urlParent && identifierParent.parentNode === urlParent.parentNode) {
                identifierParent.parentNode.insertBefore(urlParent, identifierParent);
              }
              updateFromUrl();
            }

            const button = document.getElementById('git-mirror-generate-ssh-key');
            if (!button || button.dataset.ready) return;
            button.dataset.ready = '1';
            button.addEventListener('click', async () => {
              button.disabled = true;
              button.textContent = #{l(:text_git_mirror_generating_ssh_key).to_json};
              try {
                const response = await fetch(#{generate_key_url.to_json}, {
                  method: 'POST',
                  headers: {'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''},
                  body: JSON.stringify({project_identifier: #{project_identifier.to_json}, repository_identifier: document.getElementById('repository_identifier')?.value || ''})
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.error || 'SSH key generation failed');
                document.getElementById('repository_ssh_key_path').value = result.path;
                document.getElementById('git_mirror_ssh_public_key').value = result.public_key;
                button.textContent = #{l(:text_git_mirror_generated_ssh_key).to_json};
              } catch (error) {
                button.disabled = false;
                button.textContent = #{l(:button_git_mirror_generate_ssh_key).to_json};
                alert(error.message);
              }
            });
          })();

          (() => {
            const button = document.getElementById('git-mirror-generate-webhook-secret');
            if (!button || button.dataset.ready) return;
            button.dataset.ready = '1';
            button.addEventListener('click', async () => {
              button.disabled = true;
              try {
                const response = await fetch(#{generate_secret_url.to_json}, {
                  method: 'POST',
                  headers: {'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''},
                  body: JSON.stringify({project_identifier: #{project_identifier.to_json}})
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.error || 'Webhook secret generation failed');
                document.getElementById('repository_webhook_secret').value = result.secret;
              } catch (error) {
                alert(error.message);
              } finally {
                button.disabled = false;
              }
            });
          })();
        JS
      end
    end
  end
end
