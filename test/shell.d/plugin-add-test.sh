#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_plugin() {
  local dir="$1"
  local id="$2"
  local name="$3"

  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "$name",
    "category": "Test",
    "allowMultiple": false
  }
}
JSON
  printf 'import QtQuick\nItem {}\n' >"$dir/Widget.qml"
}

stub_dir="$TMPDIR/stubs"
mkdir -p "$stub_dir"
cat >"$stub_dir/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_dir/omarchy-shell"

test_home="$TMPDIR/home"
write_plugin "$test_home/.config/omarchy/plugins/different-folder" "acme.same" "Installed"

incoming="$TMPDIR/incoming"
write_plugin "$incoming" "acme.same" "Incoming"
git -C "$incoming" init -q
git -C "$incoming" add .
git -C "$incoming" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-add "$incoming" --yes 2>&1) &&
  fail "plugin add accepts an id already installed under another directory" "$output"
grep -qF "plugin id 'acme.same' is already used by" <<<"$output" ||
  fail "plugin add explains the installed id collision" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.same ]] ||
  fail "plugin add leaves a target behind after refusing a duplicate id"
pass "plugin add refuses an installed manifest id regardless of directory name"

# --- URL transport-helper guard -------------------------------------------
#
# The guard refuses git transport helpers (`<name>::…`) and option-shaped URLs
# before `git clone` runs, matching omarchy-theme-install. A git stub records
# whether clone was reached, so the guard is exercised with no network: reaching
# the stub proves a URL passed the guard; not reaching it proves the guard
# rejected the URL first.

guard_stubs="$TMPDIR/guard-stubs"
mkdir -p "$guard_stubs"
cat >"$guard_stubs/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$guard_stubs/omarchy-shell"

clone_marker="$TMPDIR/git-clone-reached"
cat >"$guard_stubs/git" <<STUB
#!/bin/bash
if [[ \$1 == "clone" ]]; then
  touch "$clone_marker"
  exit 1
fi
exit 0
STUB
chmod +x "$guard_stubs/git"

add_url() {
  HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$guard_stubs:$ROOT/bin:$PATH" \
    omarchy-plugin-add "$1" --yes 2>&1
}

# Transport helpers reach the guard, are named as such, and never reach clone.
for bad in "ext::sh -c touch /tmp/omarchy-guard-test" "fd::17"; do
  rm -f "$clone_marker"
  output=$(add_url "$bad") &&
    fail "plugin add rejects a transport-helper URL: $bad" "$output"
  grep -qF "names a git option or transport helper" <<<"$output" ||
    fail "plugin add names the transport-helper rejection: $bad" "$output"
  [[ ! -e $clone_marker ]] ||
    fail "plugin add reached git clone for a transport-helper URL: $bad"
done
pass "plugin add rejects transport-helper URLs before cloning"

# Option-shaped URLs are refused before clone (argv hits the option parser; the
# guard covers the same shape from the interactive gum prompt).
for bad in "-oProxyCommand=x" "--upload-pack=x"; do
  rm -f "$clone_marker"
  output=$(add_url "$bad") &&
    fail "plugin add rejects an option-shaped URL: $bad" "$output"
  [[ ! -e $clone_marker ]] ||
    fail "plugin add reached git clone for an option-shaped URL: $bad"
done
pass "plugin add rejects option-shaped URLs before cloning"

# Legitimate URL forms pass the guard and reach git clone (stubbed, no network).
for good in \
  "https://github.com/acme/omarchy-weather.git" \
  "git@github.com:acme/repo.git" \
  "ssh://git@github.com/acme/repo.git" \
  "git@[2001:db8::1]:org/repo.git"; do
  rm -f "$clone_marker"
  output=$(add_url "$good") || true
  ! grep -qF "names a git option or transport helper" <<<"$output" ||
    fail "plugin add wrongly rejected a legitimate URL: $good" "$output"
  [[ -e $clone_marker ]] ||
    fail "plugin add did not reach git clone for a legitimate URL: $good" "$output"
done
pass "plugin add lets legitimate git URLs reach git clone"
