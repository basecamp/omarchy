#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mock_bin="$test_tmp/bin"
mise_log="$test_tmp/mise"
mise_config="$test_tmp/etc/mise/config.toml"
mkdir -p "$test_home/.local/bin" "$mock_bin"

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_LOG"
SH
chmod +x "$mock_bin/mise"

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$mock_bin/sudo"

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_MISE_CONFIG_PATH="$mise_config"
export OMARCHY_TEST_MISE_LOG="$mise_log"
export PATH="$mock_bin:$PATH"

write_wrapper() {
  local package=$1 command=$2 bin
  bin=${3:-$command}

  cat >"$test_home/.local/bin/$command" <<EOF
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "$package" || exit 1
exec mise x "$package" -- "$bin" "\$@"
EOF
  chmod +x "$test_home/.local/bin/$command"
}

write_wrapper codex codex
write_wrapper npm:playwright playwright
write_wrapper github:can1357/oh-my-pi omp
write_wrapper aqua:google-antigravity/antigravity-cli agy
cat >"$test_home/.local/bin/hunk" <<'SH'
#!/bin/bash
echo user-owned
SH
chmod +x "$test_home/.local/bin/hunk"

bash -euo pipefail "$ROOT/migrations/1788262200.sh" >/dev/null

for command in codex playwright omp agy; do
  [[ ! -e $test_home/.local/bin/$command ]] || fail "lazy-tool migration removes the recognized $command wrapper"
done
grep -Fx 'echo user-owned' "$test_home/.local/bin/hunk" >/dev/null || fail "lazy-tool migration preserves a user-owned command"
[[ -f $mise_config ]] || fail "lazy-tool migration installs the system mise config"
grep -Fx 'locked_scopes = ["project", "global"]' "$mise_config" >/dev/null ||
  fail "lazy-tool migration excludes system tools from invocation-wide locked mode"
grep -Eq '^uv = \{ version = "latest", lazy = true, minimum_release_age = "0s" \}$' "$mise_config" ||
  fail "lazy-tool migration declares uv"
[[ $(grep -c 'lazy = true' "$mise_config") == 16 ]] || fail "lazy-tool migration declares every default tool"
grep -Fx 'reshim --system' "$mise_log" >/dev/null || fail "lazy-tool migration reconciles bootstrap shims"
pass "lazy-tool migration replaces recognized wrappers with native lazy declarations"

: >"$mise_log"
bash -euo pipefail "$ROOT/migrations/1788262200.sh" >/dev/null
[[ -f $mise_config ]] || fail "lazy-tool migration remains installed on a second run"
grep -Fx 'echo user-owned' "$test_home/.local/bin/hunk" >/dev/null || fail "lazy-tool migration remains safe on a second run"
[[ $(grep -c '^reshim --system$' "$mise_log") == 1 ]] || fail "lazy-tool migration reshims once on a second run"
pass "lazy-tool migration is idempotent"

mkdir -p "$test_home/.local/state/omarchy"
touch "$test_home/.local/state/omarchy/preinstalls-removed"
write_wrapper npm:@kitlangton/ghui ghui
rm -f "$mise_config"
: >"$mise_log"
bash -euo pipefail "$ROOT/migrations/1788262200.sh" >/dev/null
[[ ! -e $mise_config ]] || fail "lazy-tool migration honors the preinstall opt-out"
[[ ! -e $test_home/.local/bin/ghui ]] || fail "lazy-tool migration removes an obsolete wrapper after opt-out"
grep -Fx 'reshim --system' "$mise_log" >/dev/null || fail "lazy-tool migration removes obsolete bootstrap shims after opt-out"
pass "lazy-tool migration preserves the preinstall opt-out"
