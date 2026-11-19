#!/usr/bin/env bash
# Renders templates/etc/trowel/config.yml.j2 for a workspace without upstream_org, with
# upstream_org equal to org, and on forks, and checks each with `trowel -validate`.
# Writes only to a temporary directory.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { # name, extra vars...
  local name=$1; shift
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible localhost -c local -m ansible.builtin.template \
    -a "src=$root/templates/etc/trowel/config.yml.j2 dest=$tmp/$name.yml" \
    -e "workspace=ws org=boblangley nats_url=nats://x:4222" "$@" >/dev/null
  trowel -validate -config "$tmp/$name.yml" >/dev/null 2>&1
}
fail() { echo "FAIL: $*" >&2; exit 1; }

render none
render same -e upstream_org=boblangley
render empty -e upstream_org=
render forks -e upstream_org=wyrd-company

for n in none same empty; do
  ! grep -q -- 'name: .*-upstream$' "$tmp/$n.yml" || fail "$n: unexpected upstream subject"
  ! grep -q 'name: fork-sync' "$tmp/$n.yml" || fail "$n: unexpected fork-sync"
done
[ "$(grep -c -- 'name: .*-upstream$' "$tmp/forks.yml")" = 4 ] || fail "forks: want 4 upstream subjects"
for r in workspace-ansible workspace-dotfiles skills workflows; do
  grep -q "subject: github.wyrd-company.$r.push.none" "$tmp/forks.yml" || fail "forks: no subject for $r"
  grep -q "\"FORK\": \"boblangley/$r\"" "$tmp/forks.yml" || fail "forks: no FORK for $r"
done
echo ok
