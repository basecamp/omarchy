#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Regenerate noisy mise wrappers so they stop writing to stdout' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "noisy mise wrapper migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export HOME="$TMPDIR"
export PATH="$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
mkdir -p "$HOME/.local/bin"

# Exact pre--quiet stub — must be regenerated.
cat >"$HOME/.local/bin/gh" <<'SH'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "gh" || exit 1
exec mise x "gh" -- "gh" "$@"
SH
chmod +x "$HOME/.local/bin/gh"

# Already quiet — leave alone.
cat >"$HOME/.local/bin/codex" <<'SH'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "codex" || exit 1
exec mise x "codex" -- "codex" "$@"
SH
chmod +x "$HOME/.local/bin/codex"
codex_before=$(<"$HOME/.local/bin/codex")

# Custom script that calls mise — must not be overwritten.
cat >"$HOME/.local/bin/mytool" <<'SH'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "gh" || exit 1
echo custom setup
exec mise x "gh" -- "gh" "$@"
SH
chmod +x "$HOME/.local/bin/mytool"
mytool_before=$(<"$HOME/.local/bin/mytool")

bash -euo pipefail "$migration" >/dev/null || fail "migration exits clean"

grep -Fq 'mise use -g --quiet "gh"' "$HOME/.local/bin/gh" ||
  fail "legacy wrapper regenerated with --quiet"
[[ $(<"$HOME/.local/bin/codex") == "$codex_before" ]] ||
  fail "already-quiet wrapper left alone"
[[ $(<"$HOME/.local/bin/mytool") == "$mytool_before" ]] ||
  fail "custom mise script left alone"
pass "migration rewrites only exact legacy mise stubs"
