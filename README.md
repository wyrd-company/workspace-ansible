# workspace-ansible
Ansible playbooks for workspaces

The playbook provides the root-owned Xolotl MCP configuration: Codex's connection
in `/etc/codex/config.toml` and `/usr/local/bin/xolotl-mcp-headers`. The helper reads
the workspace's key from `kv/xolotl/keys/<xolotl_key>` through Wyrwood with
`bao` and returns a JSON Authorization header. No key is saved in client
configuration. The key's Xolotl policy must grant the `mcp` scope and allow the
upstream servers in `mcp_servers`.

Codex uses `http_headers_helper` and sets the Wyrwood socket address explicitly
because Codex does not pass `BAO_ADDR` or `VAULT_ADDR` to the helper.
Claude Code's user-owned connection in
`~/.claude.json` is managed by workspace-dotfiles, which reads `xolotl_url` from
`/etc/workspace/config.yml` and uses the same helper as `headersHelper`. Claude's
`managedMcpServers` setting rejects header helpers, and `managed-mcp.json`
would disable plugin servers such as mnemonic. Root configuration belongs here;
user configuration belongs in workspace-dotfiles. Run `ansible-sync` to apply
the configuration to an existing workspace, then start a new client session.

The playbook owns `$CARGO_HOME/config.toml` and caps cargo at 4 parallel compile
jobs, since agents build at once. `CARGO_HOME` (`/usr/local/cargo`) is a bind mount
of the host's shared cargo cache, so the cap reaches every workspace on the host.
Override it for one build with `-j N` or `CARGO_BUILD_JOBS=N`.
Workspaces without Rust have no cargo home, and the playbook skips the cap there.

Grok reads `/etc/grok/managed_config.toml`: the grok-4.7 model route through Xolotl (the
model key comes from `/usr/local/bin/xolotl-api-key`, which reads it through Wyrwood on demand), the
git-operator SessionStart hook and the mnemonic MCP server. Its Xolotl MCP connection
uses `headers_helper` (Grok Build 1.0.88 and later), with the same helper as Codex and Claude Code.

The installed Toha `project` template asks for an optional remote URL. Toha
initializes the project as a Git repository even when the URL is empty, so it can
save `.toha.json` for template tracking and updates. A target already inside a
repository uses that repository unchanged.

Apply the `repo` template inside a project. It uses the project's Git repository
and records its application in the project's `.toha.json`, without asking for a
separate remote or initializing another setup repository. The cloned repository
keeps its own remote and history.

Both templates register their folder as a T3 Code project through
`ensure-t3-project`, which the playbook installs in `/usr/local/bin`. A project
folder is named `$WORKSPACE_NAME <project>`, and its after-apply message asks for
an icon to be set with T3's `t3_project_update`, since the `t3` CLI cannot set
one. A repo folder is named for the repository; when the default branch
worktree has an icon, in one of T3 Code's own locations or under
`docs/user/assets/`, the hook records it as `iconPath` in the repo folder's
`t3.json`; without one, the after-apply message asks for an icon as for a
project folder. A folder that is already a T3 project keeps its title. The hook skips
the temporary checkouts of toha's `--update` and `--baseline` modes, and does
nothing where there is no `t3` CLI.

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

Trowel wakes T3 Code threads for their Discord conversations. Its `<workspace>-deck`
relay consumes the deck service's `DECK` stream (`deck.>`) and runs
`/usr/local/bin/deck-wake-t3` with each activity event on stdin. The helper runs
`deck resolve` against the workspace's own deck store, from the client
configuration workspace-dotfiles manages, and sends each resolved session with a
`T3CODE_THREAD_ID` a notice through `t3 thread send`, asking it to run
`deck read`. The notice carries no Discord content. Discord's thread starter
reference (message type 21), which opens a thread started from a text channel
message, is skipped, so a post does not wake the thread that made it. Activity in a thread no local
session touched resolves to no session and wakes nothing, so every workspace can
consume every event. A failed resolve or send fails the delivery, and Trowel
retries it. Run `DECK_WAKE_T3_DRY_RUN=1 deck-wake-t3 < activity.json` to see the
sends without making them.

A workspace on forks adds its own vars, `/etc` templates and tasks under `fork/`, which
upstream never commits to; see [docs/fork-overlay.md](docs/fork-overlay.md).
