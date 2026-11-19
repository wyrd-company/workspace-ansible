#!/usr/bin/env bash
# Checks the fork overlay of container.yml (docs/fork-overlay.md) against a throwaway fork/ folder,
# rendering into a temporary directory instead of /etc. Never runs the real playbook.
#
# The overlay tasks are taken from container.yml itself: the script copies the play's tasks from
# "Load variables from workspace options" to "Render and deploy templates to /etc" and from
# "Find the fork's tasks" on into a temporary playbook, with /etc moved into the temporary
# directory and ownership and privilege escalation removed.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/play/templates" "$tmp/etc" "$tmp/out"
# Only the trowel template: the others need workspace vars this test does not have
mkdir -p "$tmp/play/templates/etc/trowel"
cp "$root/templates/etc/trowel/config.yml.j2" "$tmp/play/templates/etc/trowel/"
mkdir -p "$tmp/play/templates/etc/demo"
echo 'upstream {{ who }}' > "$tmp/play/templates/etc/demo/shadowed.conf.j2"
echo 'upstream only' > "$tmp/play/templates/etc/demo/upstream-only.conf.j2"
printf 'workspace: ws\norg: boblangley\nnats_url: nats://x:4222\nwho: upstream\n' > "$tmp/etc/config.yml"

"$(head -1 "$(command -v ansible-playbook)" | sed 's/^#! *//')" -I - "$root/container.yml" "$tmp" <<'PY'
import sys, yaml
src, tmp = sys.argv[1:]
play = yaml.safe_load(open(src))[0]
tasks = play["tasks"]
root_block = next(t for t in tasks if t["name"] == "Apply system-wide configurations as root")
inner = root_block["block"]
inames = [t["name"] for t in inner]
keep = [t for t in tasks if t["name"] in (
    "Load variables from workspace options", "Look for the fork overlay", "Load the fork's variables",
    "Find the fork's tasks", "Run the fork's tasks")]
block = inner[: inames.index("Render and deploy templates to /etc") + 1]
for t in block:
    for module in t.values():
        if isinstance(module, dict):
            module.pop("owner", None); module.pop("group", None)
    t.pop("become", None)
    if "ansible.builtin.file" in t:
        t["ansible.builtin.file"]["path"] = t["ansible.builtin.file"]["path"].replace('"/etc/', '"' + tmp + '/out/etc/')
first = [t for t in keep if t["name"] != "Find the fork's tasks" and t["name"] != "Run the fork's tasks"]
last = [t for t in keep if t["name"] in ("Find the fork's tasks", "Run the fork's tasks")]
out = [{"name": "overlay", "hosts": "localhost", "connection": "local", "gather_facts": False,
        "tasks": first + [{"name": "root", "vars": root_block["vars"], "block": block}] + last}]
body = yaml.safe_dump(out).replace("/etc/workspace/config.yml", tmp + "/etc/config.yml")
body = body.replace("/etc/{{", tmp + "/out/etc/{{").replace('"/etc/{{', '"' + tmp + '/out/etc/{{')
open(tmp + "/play/play.yml", "w").write(body)
PY

run() { ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
  ansible-playbook "$tmp/play/play.yml" "$@" >"$tmp/log" 2>&1 || { cat "$tmp/log"; fail "playbook failed"; }; }
fail() { echo "FAIL: $*" >&2; exit 1; }
out=$tmp/out/etc

# 1. No fork/: upstream only
run
[ "$(cat "$out/demo/shadowed.conf")" = "upstream upstream" ] || fail "no fork: upstream template not rendered"
[ -f "$out/trowel/config.yml" ] || fail "no fork: trowel config missing"

# 2. A fork overlay
rm -rf "$out"
f=$tmp/play/fork
mkdir -p "$f/templates/etc/demo" "$f/templates/etc/trowel" "$f/templates/etc/fork-only" "$f/tasks"
echo 'who: fork' > "$f/vars.yml"
echo 'fork {{ who }} {{ org }}' > "$f/templates/etc/demo/shadowed.conf.j2"
echo 'fork only {{ who }}' > "$f/templates/etc/fork-only/new.conf.j2"
echo 'fork trowel' > "$f/templates/etc/trowel/config.yml.j2"
cat > "$f/tasks/20-second.yml" <<EOT
- ansible.builtin.lineinfile: {path: $tmp/order, line: "second {{ who }}", create: true}
EOT
cat > "$f/tasks/10-first.yml" <<EOT
- ansible.builtin.lineinfile: {path: $tmp/order, line: first, create: true}
EOT
echo '- fail: {msg: not a task file}' > "$f/tasks/notes.txt"
run
[ "$(cat "$out/demo/shadowed.conf")" = "fork fork boblangley" ] || fail "fork template did not replace upstream (or vars did not override)"
[ "$(cat "$out/demo/upstream-only.conf")" = "upstream only" ] || fail "upstream-only template lost"
[ "$(cat "$out/fork-only/new.conf")" = "fork only fork" ] || fail "fork-only template missing"
[ "$(cat "$out/trowel/config.yml")" = "fork trowel" ] || fail "fork trowel config did not replace upstream"
[ "$(cat "$tmp/order")" = "$(printf 'first\nsecond fork')" ] || fail "fork tasks not run in sorted order"
echo ok
