# Fork overlay

A workspace can run on forks: its repositories under `org` are forks of the same-named
repositories under `upstream_org` (see the standard in
[wyrd-company/skills#32](https://github.com/wyrd-company/skills/pull/32)). This repository
reserves three paths for a fork's own changes. Upstream never commits under `fork/`, so a fork
that commits there never conflicts when it syncs `main`.

All of `fork/` is optional. Without it, the playbook behaves as it does for upstream.

| Path | Combines with upstream | Used by |
| --- | --- | --- |
| `fork/vars.yml` | Merged: loaded after `/etc/workspace/config.yml`, so it overrides | The whole play |
| `fork/templates/etc/**.j2` | Added, or replacing the upstream template with the same relative path | `/etc` rendering |
| `fork/tasks/*.yml` | Added: run after everything else, in sorted order | The end of the play |

There is no `.gitignore` entry or placeholder file for `fork/`: either would get in the way of
the fork committing there.

## `fork/vars.yml`

A YAML mapping, loaded with `include_vars` right after `/etc/workspace/config.yml`. A key
that is in both takes the fork's value. It is loaded before any template is rendered, so
templates, upstream's and the fork's, see it.

```yaml
# fork/vars.yml
dotfiles_repo: git@github.com:boblangley/workspace-dotfiles.git
```

## `fork/templates/etc/**.j2`

Rendered to `/etc` the way `templates/etc` is: `fork/templates/etc/foo/bar.conf.j2` becomes
`/etc/foo/bar.conf`, owned by root, mode `0644`, with the same variables.

A fork template whose path relative to `fork/templates/etc` equals an upstream one's
**replaces** it. The playbook picks one source per target before it renders anything, so the
upstream file is not rendered at all and the result does not depend on render order. Any other
fork template is added.

Trowel is reloaded when a rendered file under `/etc/trowel/` changed, whichever source it
came from, so a fork's Trowel config counts too.

### Example: a fork-only Trowel relay

Trowel reads `/etc/trowel/config.yml`, so a fork cannot add a subject next to upstream's without
replacing the file. Copy upstream's `templates/etc/trowel/config.yml.j2` to
`fork/templates/etc/trowel/config.yml.j2` and add the relay to the list it loops over:

```jinja
{% for relay in [
  {'name': 'ansible', 'repo': 'workspace-ansible', 'dag': 'workspace-update-ansible'},
  ...
  {'name': 'my-tool', 'repo': 'my-tool', 'dag': 'workspace-update-my-tool'},
] %}
```

The copy then replaces upstream's, so merge upstream's later changes to the file into it
(a sync that changes `templates/etc/trowel/config.yml.j2` does not touch the copy). Keep the
`-upstream` block that follows the relay's subject if the relay's repository is a fork too.

## `fork/tasks/*.yml`

Every `*.yml` directly in `fork/tasks/` is included with `include_tasks`, in sorted file name
order, as the last tasks of the play: after `/etc` is rendered, the dotfiles applied, the
repositories checked out and the Toha templates installed. Prefix names with numbers to order
them. Other file types, and subfolders, are ignored.

Tasks run as the user that runs the playbook (root under `ansible-sync`) and with the play's
variables, `fork/vars.yml` included. Set `become` where a task needs another user.

```yaml
# fork/tasks/10-tool.yml
- name: Install my-tool
  ansible.builtin.command:
    argv: [brew, install, my-tool]
    creates: /home/linuxbrew/.linuxbrew/bin/my-tool
  become: true
  become_user: vscode
```

## Trowel subjects for upstream pushes

Not an overlay path, but part of running on forks: when `upstream_org` is set in
`/etc/workspace/config.yml` and differs from `org`, `templates/etc/trowel/config.yml.j2` adds a
`<workspace>-<name>-upstream` subject for each relay. A push to the upstream repository
enqueues `fork-sync` (workflows repository, `sub-dags/fork-sync.yml`), which brings the fork's
`main` up to date; the fork's own push subject then applies the result.

## Tests

`tests/trowel-upstream.sh` renders the Trowel template with and without `upstream_org` and
validates each result with `trowel -validate`. `tests/fork-overlay.sh` runs the overlay
tasks of `container.yml` against a throwaway `fork/` folder and a temporary destination.
Both need `ansible` and `trowel`, change nothing outside a temporary directory and do not run the
playbook.
