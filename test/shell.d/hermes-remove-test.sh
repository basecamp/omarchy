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

# Installed but never launched: the app never wrote these, so they are somebody
# else's and must survive.
seed_install
printf '%s\n' "#!/bin/bash" "exec /usr/local/bin/my-own-hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds with a foreign hermes present"
[[ -f $test_home/.local/bin/hermes ]] ||
  fail "a hermes command the app did not write survives removal"
pass "removal leaves a hermes it does not own"
