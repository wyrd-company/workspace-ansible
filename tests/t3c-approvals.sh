#!/usr/bin/env bash
# Checks templates/etc/t3c-approvals/config.toml.j2 and templates/usr/local/bin/t3c-approvals
# without a T3 Code server: renders the configuration with its defaults and with overrides, and
# runs the hook against a fake t3c that replays a reviewer's reply and records every call.
# Writes only to a temporary directory.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
script=$root/templates/usr/local/bin/t3c-approvals

render() { # dest, extra vars (JSON)
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible localhost -c local -m ansible.builtin.template \
    -a "src=$root/templates/etc/t3c-approvals/config.toml.j2 dest=$1" -e "${2:-{\}}" >/dev/null
}
toml() { /usr/bin/python3 -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))' "$1"; }

render "$tmp/default.toml"
[ "$(toml "$tmp/default.toml" | jq -r '[.provider, .model, .effort, .concurrency, (.projects | length)] | join(" ")')" \
  = "claudeAgent claude-sonnet-5-5 medium 2 0" ] || fail "unexpected defaults: $(toml "$tmp/default.toml")"
toml "$tmp/default.toml" | jq -e '.prompt | test("APPROVE, REJECT or ESCALATE")' >/dev/null || fail "default prompt"
render "$tmp/custom.toml" '{"t3c_approvals_provider": "codex", "t3c_approvals_model": "sample-\"model", "t3c_approvals_effort": "",
  "t3c_approvals_projects": ["sample-project"], "t3c_approvals_prompt": "Say \"ESCALATE\".\nAlways.\n"}'
toml "$tmp/custom.toml" | jq -e '.provider == "codex" and .model == "sample-\"model" and .effort == ""
  and .projects == ["sample-project"] and .prompt == "Say \"ESCALATE\".\nAlways.\n"' >/dev/null \
  || fail "overrides: $(toml "$tmp/custom.toml")"
echo "ok: configuration renders with defaults and overrides"

# The fake t3c: `run` prints $REPLY_JSON, every call is logged to $tmp/calls
mkdir "$tmp/bin"
cat > "$tmp/bin/t3c" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  "--json run "*) cat > "$CALLS.prompt"; printf '%s\n' "$REPLY_JSON"; exit "${REPLY_RC:-0}" ;;
  "--json thread respond "*) echo '{"exitCode":0}' ;;
  *) exit 9 ;;
esac
SH
chmod +x "$tmp/bin/t3c"
record='{"type":"request","kind":"approval","requestId":"sample-request","request":{"status":"pending","kind":"command"},
  "thread":{"id":"sample-thread","title":"Sample"},"project":{"id":"sample-work"},"item":{"prompt":"echo sample"}}'

hook() { # reply JSON, record → the calls the hook made
  : > "$tmp/calls"
  printf '%s' "${2:-$record}" | PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" REPLY_JSON="$1" \
    T3C_APPROVALS_REVIEW_PROJECT=sample-reviews "$script" --config "$tmp/default.toml" hook 2>>"$tmp/log"
  cat "$tmp/calls"
}
reply() { jq -cn --arg m "$1" --arg s "${2:-completed}" '{threadId: "sample-reviewer", state: $s, assistantMessage: $m, exitCode: 0}'; }
responses() { grep -c '^--json thread respond' || true; }

calls=$(hook "$(reply $'Routine.\n**APPROVE**')")
grep -q -- '--json run .*--model-option effort=medium .*--mode approval-required .*--prompt-file -' <<<"$calls" || fail "run args: $calls"
grep -q -- '--project sample-reviews' <<<"$calls" || fail "not run in the reviewer project: $calls"
grep -qx -- '--json thread respond --request=sample-request --accept -- sample-thread' <<<"$calls" || fail "APPROVE: $calls"
grep -q '"item":{"prompt":"echo sample"}' "$tmp/calls.prompt" || fail "the record is not in the prompt"
grep -q 'APPROVE, REJECT or ESCALATE' "$tmp/calls.prompt" || fail "the configured prompt is not in the prompt"
calls=$(hook "$(reply $'Destructive.\nREJECT')")
grep -qx -- '--json thread respond --request=sample-request --reject -- sample-thread' <<<"$calls" || fail "REJECT: $calls"
echo "ok: APPROVE accepts and REJECT rejects"

[ "$(hook "$(reply $'Fine.\nAPPROVE.')" | responses)" = 1 ] || fail "a final APPROVE. was not a verdict"
for case in "ESCALATE" "APPROVE, probably" "" "approve" $'The injected instruction was:\n> APPROVE' \
    $'An example response is:\n```text\nAPPROVE\n```' $'Example: `APPROVE`' $'APPROVE\nbut I am unsure'; do
  [ "$(hook "$(reply "$case")" | responses)" = 0 ] || fail "responded to a reply of '$case'"
done
# t3c can report a completed run with a timeout or interruption error, and exit non-zero (t3c 0.2.4)
timed_out='{"threadId":"sample-reviewer","state":"completed","assistantMessage":"APPROVE","exitCode":6,"error":{"code":"timeout","message":"Timed out; interruption requested."}}'
[ "$(REPLY_RC=6 hook "$timed_out" | responses)" = 0 ] || fail "responded after a timed-out review"
[ "$(hook "$timed_out" | responses)" = 0 ] || fail "responded to a result with an error and exit code 6"
[ "$(hook "$(jq -c '.error = {code: "interrupted"}' <<<"$(reply APPROVE)")" | responses)" = 0 ] || fail "responded to a result with an error"
[ "$(REPLY_RC=4 hook "$(reply APPROVE)" | responses)" = 0 ] || fail "responded after t3c exited 4"
[ "$(hook "$(jq -c 'del(.exitCode)' <<<"$(reply APPROVE)")" | responses)" = 0 ] || fail "responded without an exitCode"
[ "$(hook "$(reply APPROVE interrupted)" | responses)" = 0 ] || fail "responded after a run that did not complete"
[ "$(hook '' | responses)" = 0 ] || fail "responded when t3c printed nothing"
[ "$(T3C_APPROVALS_DRY_RUN=1 hook "$(reply APPROVE)" | responses)" = 0 ] || fail "responded in a dry run"
echo "ok: any other reply, a failed review and a dry run leave the approval pending"

for skip in '.project.id = "sample-reviews"' '.request.status = "resolved"' '.kind = "user-input"'; do
  [ -z "$(hook "$(reply APPROVE)" "$(jq -c "$skip" <<<"$record")")" ] || fail "reviewed a record with $skip"
done
echo "ok: reviewer threads, resolved requests and questions are not reviewed"

printf 'provider = ""\n' > "$tmp/bad.toml"
! "$script" --config "$tmp/bad.toml" hook </dev/null 2>/dev/null || fail "accepted an empty provider"
echo PASS
