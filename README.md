# workspace-ansible
Ansible playbooks for workspaces

The installed Toha `project` and `repo` templates ask for an optional remote URL
for their setup folder. Toha initializes the target as a Git repository even
when the URL is empty, so it can save `.toha.json` for template tracking and
updates. A target already inside a repository uses that repository unchanged.
For `repo`, this URL is separate from the remote of the repository being cloned.

The generated ignore rules exclude nested clones and worktrees while keeping
the setup files and template record available for version control.
