# workspace-ansible
Ansible playbooks for workspaces

The installed Toha `project` template asks for an optional remote URL. Toha
initializes the project as a Git repository even when the URL is empty, so it can
save `.toha.json` for template tracking and updates. A target already inside a
repository uses that repository unchanged.

Apply the `repo` template inside a project. It uses the project's Git repository
and records its application in the project's `.toha.json`, without asking for a
separate remote or initializing another setup repository. The cloned repository
keeps its own remote and history.

The generated ignore rules exclude nested clones and worktrees while keeping
the setup files and template record available for version control.

The `project` template also adds a `.mnemonic` exception to `memory/.gitignore`,
so shared memories can be tracked even when a user's global ignore file excludes
`.mnemonic/`. Reapplying the template repairs existing memory worktrees without
replacing their ignore rules. Mnemonic's own exclusions inside `.mnemonic/`
continue to apply.
