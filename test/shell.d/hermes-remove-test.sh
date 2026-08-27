#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_DROP_LOG"
SH
chmod +x "$mock_bin"/*

seed_install() {
  rm -rf "$test_home"
  mkdir -p "$test_home/.hermes/hermes-agent" "$test_home/.hermes/bootstrap-cache" \
    "$test_home/.hermes/bin" "$test_home/.hermes/node/bin" \
    "$test_home/.hermes/memories" "$test_home/.hermes/sessions" \
    "$test_home/.config/Hermes" "$test_home/.local/bin"
  printf 'chat\n' >"$test_home/.hermes/sessions/one.json"
  printf 'memory\n' >"$test_home/.hermes/memories/one.md"
  printf 'soul\n' >"$test_home/.hermes/SOUL.md"
  printf 'uv\n' >"$test_home/.hermes/bin/uv"
  ln -sf "$test_home/.hermes/node/bin/node" "$test_home/.local/bin/node"
  ln -sf "$test_home/.hermes/node/bin/npm" "$test_home/.local/bin/npm"
  ln -sf /usr/bin/npx "$test_home/.local/bin/npx"
  printf 'node\n' >"$test_home/.hermes/node/bin/node"
  touch "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
}

remove() {
  OMARCHY_TEST_DROP_LOG="$test_tmp/drop-log" HOME="$test_home" PATH="$mock_bin:$PATH" \
    bash "$ROOT/bin/omarchy-remove-ai-hermes" >/dev/null 2>&1
}

# The app brings its own uv and its own node; both are runtime, not data.
seed_install
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds"
[[ ! -d $test_home/.hermes/hermes-agent ]] || fail "the runtime checkout is removed"
[[ ! -d $test_home/.hermes/bin ]] || fail "the uv the app installed is removed"
[[ ! -d $test_home/.hermes/node ]] || fail "the node the app installed is removed"
pass "removal takes the whole runtime the app installed"

[[ -d $test_home/.config/Hermes ]] ||
  fail "gateway connections, tokens and settings survive removal"
pass "removal keeps the app's connections and settings"

# -L, not -e: a dangling symlink fails -e while very much still being there.
[[ ! -L $test_home/.local/bin/node ]] || fail "a node symlink into ~/.hermes is removed"
[[ ! -L $test_home/.local/bin/npm ]] || fail "an npm symlink into ~/.hermes is removed"
[[ -L $test_home/.local/bin/npx ]] || fail "an npx symlink pointing elsewhere survives"
pass "removal clears only the managed Node links it stranded"

[[ -f $test_home/.hermes/sessions/one.json ]] || fail "chats survive removal"
[[ -f $test_home/.hermes/memories/one.md ]] || fail "memories survive removal"
[[ -f $test_home/.hermes/SOUL.md ]] || fail "SOUL.md survives removal"
pass "removal keeps what belongs to the user"

[[ ! -e $test_home/.local/bin/hermes ]] || fail "the app's own hermes command is removed"
pass "removal takes the command the app installed"

# A hermes command the app did not write survives even when the app did install
# a runtime of its own.
seed_install
printf '%s\n' "#!/bin/bash" "exec /usr/local/bin/my-own-hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds with a foreign hermes present"
[[ -f $test_home/.local/bin/hermes ]] ||
  fail "a hermes command the app did not write survives removal"
pass "removal leaves a hermes it does not own"

# Installed but never launched. The app provisions its runtime on first launch
# and marks it complete when it lands, so without that marker everything under
# ~/.hermes predates the app -- an official install, or one built by hand -- and
# the paths are identical either way. Dropping the package is the whole job.
seed_install
rm -f "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
printf 'my local edit\n' >"$test_home/.hermes/hermes-agent/PATCH"
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds when the app never finished installing Hermes"
[[ -d $test_home/.hermes/hermes-agent ]] ||
  fail "a Hermes runtime the app never installed survives removal"
[[ -f $test_home/.hermes/hermes-agent/PATCH ]] ||
  fail "local changes to a runtime the app never installed survive removal"
[[ -d $test_home/.hermes/bin && -d $test_home/.hermes/node ]] ||
  fail "the rest of a runtime the app never installed survives removal"
[[ -f $test_home/.local/bin/hermes ]] ||
  fail "the command a runtime the app never installed put on PATH survives removal"
[[ -L $test_home/.local/bin/node ]] ||
  fail "node links belonging to a runtime the app never installed survive removal"
pass "removal leaves a Hermes the app never installed"

# ~/.hermes carries a dot, so a pattern rather than a plain string would also
# claim a wrapper pointing at a sibling directory that merely looks like it.
seed_install
mkdir -p "$test_home/xhermes/bin"
sibling_body="#!/bin/bash
exec $test_home/xhermes/bin/hermes \"\$@\""
printf '%s\n' "$sibling_body" >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds with a wrapper pointing at a sibling directory"
[[ -f $test_home/.local/bin/hermes && $(cat "$test_home/.local/bin/hermes") == "$sibling_body" ]] ||
  fail "a wrapper pointing at ~/xhermes is not mistaken for one pointing into ~/.hermes"
pass "removal matches the runtime path as a plain string"
