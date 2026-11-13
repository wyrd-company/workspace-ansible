# workspace-ansible
Ansible playbooks for workspaces

The playbook provides the root-owned Xolotl MCP configuration: Codex's connection
in `/etc/codex/config.toml` and `/usr/local/bin/xolotl-mcp-headers`. The helper reads
the workspace's key from `kv/xolotl/keys/<xolotl_key>` through Wyrwood with
`bao` and returns a JSON Authorization header. No key is saved in client
configuration. The key's Xolotl policy must grant the `mcp` scope and allow the
upstream servers in `mcp_servers`.

Codex uses `http_headers_helper`. Claude Code's user-owned connection in
`~/.claude.json` is managed by workspace-dotfiles, which reads `xolotl_url` from
`/etc/workspace/config.yml` and uses the same helper as `headersHelper`. Claude's
`managedMcpServers` setting rejects header helpers, and `managed-mcp.json`
would disable plugin servers such as mnemonic. Root configuration belongs here;
user configuration belongs in workspace-dotfiles. Run `ansible-sync` to apply
the configuration to an existing workspace, then start a new client session.

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

To repair only an existing memory worktree, run
`/usr/local/share/toha/project/scripts/ensure-memory-gitignore memory` from the
project folder. Toha's `--update` and `--baseline` modes run hooks in a temporary
checkout, so they do not repair the separate memory repository in place.
