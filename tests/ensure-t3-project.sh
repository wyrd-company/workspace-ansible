#!/usr/bin/env bash
# Checks `ensure-t3-project --all` against a throwaway workspace, with a fake t3 CLI that records
# the projects it is asked to add. Never registers a real T3 project.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script=$root/templates/usr/local/bin/ensure-t3-project
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin" "$tmp/tmp"
cat >"$tmp/bin/t3" <<'T3'
#!/usr/bin/env bash
# t3 project add <path> --title <title>
echo "$3|$5" >>"$T3_LOG"
echo "Added project at $3."
T3
chmod +x "$tmp/bin/t3"

project() { # <dir> [repo[:fork]]...
    local dir=$1 apps='[{"template":"/usr/local/share/toha/project","target":"."}' spec repo branch fork
    shift
    mkdir -p "$dir/archive" "$dir/memory"
    for spec in "$@"; do
        repo=${spec%:fork}; fork=false; branch=main
        [[ "$spec" == *:fork ]] && { fork=true; branch=fork; }
        apps+=",{\"template\":\"/usr/local/share/toha/repo\",\"target\":\"$repo\",\"answers\":{\"fork\":$fork}}"
        mkdir -p "$dir/$repo/$repo.git" "$dir/$repo/$branch" "$dir/$repo/worktrees"
        touch "$dir/$repo/$branch/.git"
    done
    echo "{\"applications\":$apps]}" >"$dir/.toha.json"
}

run() { # <workspace> [--dry-run]; sets status and out
    : >"$tmp/log"
    set +e
    out=$(PATH="$tmp/bin:$PATH" TMPDIR="$tmp/tmp" T3_LOG="$tmp/log" WORKSPACE_NAME="Test" \
        "$script" --all "${@:2}" "$1" 2>&1)
    status=$?
    set -e
}

# 1. The expected layout: every project and repo folder, a hidden and a forked repo included
ws=$tmp/good
project "$ws/alpha" app .github
project "$ws/beta" upstream:fork
mkdir -p "$ws/.hidden"
touch "$ws/AGENTS.md"
mkdir -p "$ws/alpha/app/main/public" && echo '<svg/>' >"$ws/alpha/app/main/public/favicon.svg"
run "$ws"
[ "$status" -eq 0 ] || { echo "$out"; fail "good layout: exit $status"; }
expected="$ws/alpha|Test alpha
$ws/alpha/.github|.github
$ws/alpha/app|app
$ws/beta|Test beta
$ws/beta/upstream|upstream"
[ "$(sort "$tmp/log")" = "$(sort <<<"$expected")" ] || fail "good layout: registered $(cat "$tmp/log")"
[ "$(jq -r .iconPath "$ws/alpha/app/t3.json")" = "main/public/favicon.svg" ] || fail "good layout: icon not recorded"

# 2. Dry run registers nothing
run "$ws" --dry-run
[ "$status" -eq 0 ] && [ ! -s "$tmp/log" ] || fail "dry run: registered $(cat "$tmp/log")"
grep -q "Would register $ws/alpha as Test alpha" <<<"$out" || fail "dry run: no report for alpha"

# 3. Layouts that do not fit are reported, not guessed at; what does fit is still registered
ws=$tmp/bad
project "$ws/alpha" app gone noclone notree
rm -rf "$ws/alpha/gone" "$ws/alpha/noclone/noclone.git" "$ws/alpha/notree/main"
mkdir -p "$ws/alpha/stray/main" "$ws/loose-repo/main" "$ws/untracked"
echo '{"applications":[{"template":"/usr/local/share/toha/repo","target":"x"}]}' >"$ws/untracked/.toha.json"
run "$ws"
[ "$status" -eq 1 ] || { echo "$out"; fail "bad layout: exit $status, want 1"; }
for want in "$ws/alpha/gone is recorded" "$ws/alpha/noclone has no bare clone" \
    "$ws/alpha/notree has no main worktree" "$ws/alpha/stray is neither" \
    "$ws/loose-repo is not a project folder" "$ws/untracked is not a project folder" \
    "6 folder(s) in $ws do not fit"; do
    grep -qF "$want" <<<"$out" || { echo "$out"; fail "bad layout: no report: $want"; }
done
expected="$ws/alpha|Test alpha
$ws/alpha/app|app"
[ "$(sort "$tmp/log")" = "$(sort <<<"$expected")" ] || fail "bad layout: registered $(cat "$tmp/log")"

echo "ok"
