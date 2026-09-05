#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
mkdir -p "$home/.local/bin"

HOME="$home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-mise-install" claude
wrapper="$home/.local/bin/claude"

grep -qF 'mise use -g --quiet "claude@latest" || exit 1' "$wrapper" ||
  fail "mise wrapper pins the tool at @latest" "$(cat "$wrapper")"
grep -qF 'exec mise x "claude@latest" -- "claude" "$@"' "$wrapper" ||
  fail "mise wrapper executes the @latest spec" "$(cat "$wrapper")"
pass "mise wrapper refreshes to @latest on each run"

HOME="$home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-mise-install" "npm:@kitlangton/ghui" ghui
grep -qF 'mise use -g --quiet "npm:@kitlangton/ghui@latest" || exit 1' "$home/.local/bin/ghui" ||
  fail "mise wrapper appends @latest after a scoped npm package" "$(cat "$home/.local/bin/ghui")"
pass "mise wrapper appends @latest after a scoped npm package"

HOME="$home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-mise-install" "claude@1.2.3" claude-pinned
grep -qF 'mise use -g --quiet "claude@1.2.3" || exit 1' "$home/.local/bin/claude-pinned" ||
  fail "mise wrapper leaves an already-versioned spec alone" "$(cat "$home/.local/bin/claude-pinned")"
if grep -q 'claude@1.2.3@latest' "$home/.local/bin/claude-pinned"; then
  fail "mise wrapper does not append @latest onto a pinned version"
fi
pass "mise wrapper leaves an already-versioned spec alone"

HOME="$home" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-mise-install" "claude@latest" claude-latest
grep -qF 'mise use -g --quiet "claude@latest" || exit 1' "$home/.local/bin/claude-latest" ||
  fail "mise wrapper does not double @latest" "$(cat "$home/.local/bin/claude-latest")"
pass "mise wrapper does not double @latest"

migration="$ROOT/migrations/1788521802.sh"
[[ -f $migration ]] || fail "a migration rewrites existing mise wrappers onto @latest"
pass "a migration rewrites existing mise wrappers onto @latest"

bin_dir="$home/.local/bin"
cat >"$bin_dir/codex" <<'EOF'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "codex" || exit 1
exec mise x "codex" -- "codex" "$@"
EOF
chmod +x "$bin_dir/codex"

HOME="$home" PATH="$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null

grep -qF 'mise use -g --quiet "codex@latest" || exit 1' "$bin_dir/codex" ||
  fail "migration rewrites a quiet wrapper onto @latest" "$(cat "$bin_dir/codex")"
pass "migration rewrites a quiet wrapper onto @latest"

before=$(cat "$bin_dir/codex")
HOME="$home" PATH="$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
[[ $(cat "$bin_dir/codex") == "$before" ]] || fail "latest-wrapper migration is idempotent"
pass "latest-wrapper migration is idempotent"
