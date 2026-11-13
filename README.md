# workspace-ansible
Ansible playbooks for workspaces

The playbook connects Codex and Claude Code to the Xolotl MCP gateway at
`<xolotl_url>/mcp`. Both use `/usr/local/bin/xolotl-mcp-headers`, which reads
the workspace's key from `kv/xolotl/keys/<xolotl_key>` through Wyrwood with
`bao` and returns a JSON Authorization header. No key is saved in client
configuration. The key's Xolotl policy must grant the `mcp` scope and allow the
upstream servers in `mcp_servers`.

Codex reads the connection from `/etc/codex/config.toml` with
`http_headers_helper`. Claude Code uses `headersHelper` in user scope, added
with `claude mcp add-json` only when its configuration differs. Claude's
`managedMcpServers` setting rejects header helpers, and `managed-mcp.json`
would disable plugin servers such as mnemonic. User scope keeps those servers
available and preserves the user's other settings. Run `ansible-sync` to apply
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
