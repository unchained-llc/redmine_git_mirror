(() => {
  const initialize = (picker) => {
    if (picker.dataset.ready) return;
    picker.dataset.ready = '1';
    const provider = picker.querySelector('#git_mirror_provider');
    const search = picker.querySelector('#git_mirror_search');
    const list = picker.querySelector('#git_mirror_repository');
    const field = picker.querySelector('#repository_url');
    const identifier = picker.closest('form')?.querySelector('#repository_identifier');
    const form = picker.closest('form');
    const scmRow = form?.querySelector('#repository_scm')?.closest('p');
    const defaultRow = form?.querySelector('#repository_is_default')?.closest('p');
    if (scmRow && scmRow.parentElement === picker.parentElement) {
      scmRow.after(picker);
      if (defaultRow?.parentElement === picker.parentElement) picker.parentElement.append(defaultRow);
    }
    const status = picker.querySelector('.git-mirror-status');
    const previousUrl = field.value;
    const catalogs = new Map();
    let entries = [];
    let generation = 0;
    let automaticIdentifier = !identifier?.value;

    identifier?.addEventListener('input', () => { automaticIdentifier = false; });
    const select = () => {
      field.value = list.value;
      if (identifier && automaticIdentifier && list.value) {
        const name = list.selectedOptions[0].dataset.name.split('/').pop();
        let value = name.toLowerCase().replace(/[^a-z0-9_-]+/g, '-');
        if (!/^[a-z]/.test(value)) value = `repo-${value}`;
        identifier.value = value.slice(0, 255);
      }
    };
    const render = () => {
      const selected = list.value || field.value;
      const query = search.value.trim().toLowerCase();
      list.replaceChildren();
      entries.filter((entry) => entry.name.toLowerCase().includes(query)).forEach((entry) => {
        const option = document.createElement('option');
        option.value = entry.url;
        option.dataset.name = entry.name;
        option.textContent = entry.name + (entry.available ? '' : ` (${picker.dataset.unavailable})`);
        option.disabled = !entry.available;
        option.selected = entry.url === selected;
        list.appendChild(option);
      });
      // The user must choose a repository explicitly; never submit a stale URL
      // after changing providers or filtering away a previous selection.
      const match = Array.from(list.options).find((option) => option.value === selected && !option.disabled);
      list.selectedIndex = match ? match.index : -1;
      status.textContent = list.options.length ? '' : picker.dataset.empty;
      select();
    };
    const load = async () => {
      const current = ++generation;
      const name = provider.value;
      list.disabled = true;
      list.replaceChildren();
      field.value = '';
      status.textContent = picker.dataset.loading;
      try {
        if (!catalogs.has(name)) {
          const response = await fetch(picker.dataset[`${name}Url`], {headers: {'Accept': 'application/json'}});
          const data = await response.json();
          if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
          if (!Array.isArray(data)) throw new Error('Invalid repository list');
          catalogs.set(name, data);
        }
        if (current !== generation || !picker.isConnected) return;
        entries = catalogs.get(name);
        if (previousUrl && entries.some((entry) => entry.url === previousUrl)) field.value = previousUrl;
        list.disabled = false;
        render();
      } catch (error) {
        if (current === generation) status.textContent = error.message;
      }
    };
    list.addEventListener('change', select);
    search.addEventListener('input', render);
    provider.addEventListener('change', () => { search.value = ''; load(); });
    picker.closest('form')?.addEventListener('submit', (event) => {
      if (list.disabled || !field.value) {
        event.preventDefault();
        list.focus();
      }
    });
    load();
  };
  const scan = () => document.querySelectorAll('.git-mirror-picker').forEach(initialize);
  scan();
  new MutationObserver(scan).observe(document.body, {childList: true, subtree: true});
})();
