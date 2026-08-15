#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
toggle_log="$test_tmp/toggle-log"
preference="$test_home/.local/state/omarchy/settings/plugin-verification"
mkdir -p "$stub_bin" "$(dirname "$preference")" "$test_home/.agents/skills"

cat >"$stub_bin/omarchy-default-agent" <<'STUB'
#!/bin/bash
echo codex
STUB
cat >"$stub_bin/omarchy-toggle" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TOGGLE_LOG"
STUB
chmod +x "$stub_bin"/*
printf 'always\n' >"$preference"

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export TEST_TOGGLE_LOG="$toggle_log"

bash -e -c 'source "$1"' bash "$ROOT/migrations/1786793236.sh" >/dev/null
[[ ! -e $preference ]] || fail "security migration leaves the obsolete plugin preference"
grep -qxF "agent-security-scan on" "$toggle_log" || fail "security migration does not preserve an affirmative preference"
[[ $(readlink "$test_home/.agents/skills/verify-aur-package") == "$ROOT/default/agents/skills/verify-aur-package" ]] ||
  fail "security migration does not link the AUR review skill"
pass "security migration unifies the old preference and links the AUR skill"

custom="$test_tmp/custom-skill"
rm "$test_home/.agents/skills/verify-aur-package"
mkdir -p "$custom"
ln -s "$custom" "$test_home/.agents/skills/verify-aur-package"
bash -e -c 'source "$1"' bash "$ROOT/migrations/1786793236.sh" >/dev/null
[[ $(readlink "$test_home/.agents/skills/verify-aur-package") == "$custom" ]] ||
  fail "security migration overwrites a custom review skill"
pass "security migration preserves a custom AUR review skill"

rm "$test_home/.agents/skills/verify-aur-package"
ln -s "$test_home/missing-custom-skill" "$test_home/.agents/skills/verify-aur-package"
bash -e -c 'source "$1"' bash "$ROOT/migrations/1786793236.sh" >/dev/null
[[ $(readlink "$test_home/.agents/skills/verify-aur-package") == "$test_home/missing-custom-skill" ]] ||
  fail "security migration replaces a broken custom skill link"
pass "security migration preserves a temporarily broken custom skill link"
