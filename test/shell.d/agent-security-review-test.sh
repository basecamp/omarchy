#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command git

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
source_dir="$test_tmp/source"
skill="$test_tmp/review-skill.md"
count_file="$test_tmp/count"
prompt_file="$test_tmp/prompt"
mkdir -p "$stub_bin" "$test_home/.codex" "$source_dir"
printf '{}\n' >"$test_home/.codex/auth.json"
printf 'Review every file without executing it.\n' >"$skill"
printf 'safe content\n' >"$source_dir/payload"
git -C "$source_dir" init -q
git -C "$source_dir" add .
git -C "$source_dir" -c user.name=Test -c user.email=test@example.com commit -qm Initial

cat >"$stub_bin/omarchy-default-agent" <<'STUB'
#!/bin/bash
echo codex
STUB
cat >"$stub_bin/omarchy-launch-tui" <<'STUB'
#!/bin/bash
echo "security reviews must not open another TUI" >&2
exit 99
STUB
cat >"$stub_bin/omarchy-agent" <<'STUB'
#!/bin/bash
while (( $# > 0 )); do
  if [[ $1 == "--prompt" ]]; then
    prompt="$2"
    break
  fi
  shift
done
printf '%s' "$prompt" >"$TEST_PROMPT"
count=0
[[ -f $TEST_COUNT ]] && read -r count <"$TEST_COUNT"
printf '%s\n' "$((count + 1))" >"$TEST_COUNT"
status=$(grep -oE '[^[:space:]]+/status' <<<"$prompt" | head -1)
run_dir=${status%/status}
printf 'inspecting source\n' >"$run_dir/status"
printf 'Inspected every file and found no unsafe behavior.\n' >"$run_dir/full-audit"
if [[ ${TEST_MUTATE:-0} == "1" ]]; then
  printf 'changed during review\n' >>"$TEST_SOURCE/payload"
fi
printf 'safe: source is limited to its stated purpose\n' >"$run_dir/verdict"
STUB
cat >"$stub_bin/codex" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/systemd-run" <<'STUB'
#!/bin/bash
while (( $# > 0 )); do
  if [[ $1 == "--" ]]; then
    shift
    break
  fi
  shift
done
exec "$@"
STUB
cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin"/*

export HOME="$test_home"
export XDG_CACHE_HOME="$test_tmp/cache"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export TEST_COUNT="$count_file"
export TEST_PROMPT="$prompt_file"
export TEST_SOURCE="$source_dir"

review() {
  omarchy-agent-security-review \
    --kind plugin --target "$source_dir" --id test.plugin --name Test \
    --skill "$skill" --revision HEAD --worktree
}

review >/dev/null
[[ $(<"$count_file") == "1" ]] || fail "first security review calls the agent"
pass "security review calls the agent for new content"

output=$(review)
[[ $(<"$count_file") == "1" ]] || fail "unchanged security review spends another agent call"
grep -qF "Reusing an exact-content review" <<<"$output" || fail "cached security review identifies the cache hit" "$output"
pass "security review caches exact content and policy"

printf 'safe content version two\n' >"$source_dir/payload"
git -C "$source_dir" add .
git -C "$source_dir" -c user.name=Test -c user.email=test@example.com commit -qm Update
review >/dev/null
[[ $(<"$count_file") == "2" ]] || fail "changed source bypasses the review cache"
grep -qF "The last safe revision was" "$prompt_file" || fail "incremental review names its last safe revision"
pass "changed source gets an incremental review from the last safe commit"

printf 'Review checksums and every file without executing it.\n' >"$skill"
review >/dev/null
[[ $(<"$count_file") == "3" ]] || fail "changed policy reuses a stale review"
pass "changing the review policy invalidates the cache"

printf 'another source change\n' >>"$source_dir/payload"
set +e
TEST_MUTATE=1 review >"$test_tmp/output" 2>&1
status=$?
set -e
(( status == 2 )) || fail "security review accepts source changed during review" "$(<"$test_tmp/output")"
grep -qF "source changed while it was being reviewed" "$test_tmp/output" ||
  fail "security review explains its time-of-check failure" "$(<"$test_tmp/output")"
pass "security review rejects content changed before its verdict is accepted"

[[ $(stat -c '%a' "$XDG_CACHE_HOME/omarchy/agent-security-scans") == "700" ]] ||
  fail "security review cache is private"
pass "security review cache is private to the user"
