#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

grep -F 'omarchy_privileged_source_root()' "$ROOT/bin/omarchy-migrate" >/dev/null ||
  fail "omarchy-migrate resolves its tree through a trusted source root"
grep -F 'MIGRATIONS_DIR="$SOURCE_ROOT/migrations"' "$ROOT/bin/omarchy-migrate" >/dev/null ||
  fail "omarchy-migrate lists migrations from the trusted source root"
grep -F 'OMARCHY_PATH="$SOURCE_ROOT" bash -euo pipefail "$file"' "$ROOT/bin/omarchy-migrate" >/dev/null ||
  fail "omarchy-migrate passes the trusted source root to each migration"
if grep -F 'MIGRATIONS_DIR="$OMARCHY_PATH/migrations"' "$ROOT/bin/omarchy-migrate" >/dev/null; then
  fail "omarchy-migrate no longer reads migrations from a caller-controlled OMARCHY_PATH"
fi
pass "omarchy-migrate reads migrations from the trusted tree, not a caller-controlled OMARCHY_PATH"

grep -F 'source "$SOURCE_ROOT/install/helpers/browser-policy.sh"' "$ROOT/bin/omarchy-install-browser" >/dev/null ||
  fail "omarchy-install-browser sources the browser policy helper from the trusted source root"
if grep -F 'source "$OMARCHY_PATH/install/helpers/browser-policy.sh"' "$ROOT/bin/omarchy-install-browser" >/dev/null; then
  fail "omarchy-install-browser no longer sources helpers from a caller-controlled OMARCHY_PATH"
fi
pass "omarchy-install-browser sources its privileged helper from the trusted tree"

grep -F 'omarchy_privileged_source_root()' "$ROOT/install/helpers/browser-policy.sh" >/dev/null ||
  fail "browser-policy.sh resolves policy files through a trusted source root"
if grep -F 'local policies=${2:-$OMARCHY_PATH/default/firefox/policies.json}' "$ROOT/install/helpers/browser-policy.sh" >/dev/null; then
  fail "browser-policy.sh no longer installs policies from a caller-controlled OMARCHY_PATH"
fi
pass "browser policy installs read the packaged tree, not a caller-controlled OMARCHY_PATH"

grep -Fx 'UPDATEDB_CONF_PATH=/etc/updatedb.conf' "$ROOT/migrations/1784809451.sh" >/dev/null ||
  fail "the locate migration pins the config the root step rewrites"
if grep -E 'env OMARCHY_UPDATEDB_CONF_PATH|\$\{OMARCHY_UPDATEDB_CONF_PATH' "$ROOT/migrations/1784809451.sh" >/dev/null; then
  fail "the locate migration no longer forwards a caller-chosen config path to root"
fi
pass "the locate migration does not let the caller name the file root rewrites"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

evil="$test_tmp/evil-tree"
mkdir -p "$evil/migrations" "$evil/default/firefox" "$test_tmp/home"

cat >"$evil/migrations/9999999999.sh" <<'SH'
echo evil >>"$TEST_CALLS"
SH

# A poisoned OMARCHY_PATH with no dev-link authorization must fall back to the
# packaged tree. --pending only lists, so this never executes real migrations.
output=$(HOME="$test_tmp/home" OMARCHY_PATH="$evil" "$ROOT/bin/omarchy-migrate" --pending 2>/dev/null) || true
[[ $output != *"9999999999"* ]] ||
  fail "omarchy-migrate --pending ignores migrations from a poisoned OMARCHY_PATH" "$output"
[[ $output != *"$evil"* ]] ||
  fail "omarchy-migrate --pending never touches the poisoned tree" "$output"
pass "omarchy-migrate ignores a poisoned OMARCHY_PATH"

if (( EUID == 0 )); then
  pass "running as root; skipping the browser policy elevation check, which would install into system browser directories"
  exit 0
fi

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

printf 'not the packaged policies\n' >"$evil/default/firefox/policies.json"
elevation_log="$test_tmp/elevation"
: >"$elevation_log"

(
  export OMARCHY_PATH="$evil" PATH="$stub_bin:/usr/bin" ELEVATION_LOG="$elevation_log"
  source "$ROOT/install/helpers/browser-policy.sh"
  browser_policy_install_firefox_policies "$test_tmp/dist"
) >/dev/null 2>&1 || true

if grep -F "$evil" "$elevation_log"; then
  fail "browser policy install does not come from a poisoned OMARCHY_PATH" \
    "$(cat "$elevation_log")"
fi
grep -F "sudo install -m 644 -o root -g root -T /usr/share/omarchy/default/firefox/policies.json" "$elevation_log" >/dev/null ||
  fail "browser policy install comes from the packaged tree" \
    "$(cat "$elevation_log")"
pass "browser policy install ignores a poisoned OMARCHY_PATH"
