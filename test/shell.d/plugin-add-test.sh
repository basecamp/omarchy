#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
calls="$TMPDIR/calls"

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
[[ -n ${OMARCHY_TEST_CALLS:-} ]] && printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ ${1:-} == shell && ${2:-} == listPlugins ]]; then
  find "$HOME/.config/omarchy/plugins" -mindepth 2 -maxdepth 2 -name manifest.json -type f -print0 2>/dev/null |
    xargs -0 -r jq '{id: .id, name: .name, version: .version, kinds: .kinds, enabled: false, canDisable: true, firstParty: false, clonedFrom: ""}' |
    jq -s .
elif [[ ${1:-} == shell && ${2:-} == enablePlugin ]]; then
  printf 'ok\n'
fi
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

new_home() {
  test_home="$TMPDIR/home-$1"
  mkdir -p "$test_home"
}

run_add() {
  HOME="$test_home" OMARCHY_PATH="$ROOT" OMARCHY_TEST_CALLS="$calls" \
    PATH="$stub_dir:$ROOT/bin:$PATH" omarchy-plugin-add "$@"
}

assert_no_stage() {
  local stage
  stage=$(find "$test_home/.config/omarchy/plugins" -maxdepth 1 -name '.add.tmp.*' -print -quit 2>/dev/null || true)
  [[ -z $stage ]] || fail "plugin add leaves a staging directory after failure"
}

valid_source="$TMPDIR/valid-source"
write_plugin "$valid_source" acme.local "Local source"
git -C "$valid_source" init -q
git -C "$valid_source" add .
git -C "$valid_source" -c user.name=Test -c user.email=test@example.com commit -qm Initial

new_home failed-clone
if run_add "$TMPDIR/does-not-exist" --yes >/dev/null 2>&1; then
  fail "plugin add accepts a failed clone"
fi
assert_no_stage
[[ ! -e $test_home/.config/omarchy/plugins/acme.local ]] || fail "failed clone installs a plugin"
pass "failed clones leave no installed plugin or staging directory"

invalid_source="$TMPDIR/invalid-source"
mkdir -p "$invalid_source"
printf '{invalid\n' >"$invalid_source/manifest.json"
git -C "$invalid_source" init -q
git -C "$invalid_source" add .
git -C "$invalid_source" -c user.name=Test -c user.email=test@example.com commit -qm Initial
new_home invalid
if run_add "$invalid_source" --yes >/dev/null 2>&1; then
  fail "plugin add accepts an invalid manifest"
fi
assert_no_stage
[[ -z $(find "$test_home/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 ! -name '.*' -print -quit 2>/dev/null) ]] ||
  fail "invalid manifest leaves a visible installed plugin"
pass "invalid manifests leave no installed plugin or registry-visible directory"

new_home existing-destination
mkdir -p "$test_home/.config/omarchy/plugins/acme.local"
printf 'keep\n' >"$test_home/.config/omarchy/plugins/acme.local/sentinel"
if run_add "$valid_source" --yes >/dev/null 2>&1; then
  fail "plugin add overwrites an existing destination"
fi
grep -q '^keep$' "$test_home/.config/omarchy/plugins/acme.local/sentinel" ||
  fail "plugin add modifies an existing destination"
assert_no_stage
pass "existing destinations are rejected without modification"

new_home local-path
: >"$calls"
run_add "$valid_source" --yes >/dev/null
[[ -f $test_home/.config/omarchy/plugins/acme.local/manifest.json ]] ||
  fail "local path plugin is not installed"
grep -Fqx 'shell discoverPlugins acme.local' "$calls" ||
  fail "local path add does not request targeted discovery"
pass "local repository paths install through targeted discovery"

new_home remote-url
: >"$calls"
run_add "file://$valid_source" --yes --enable >/dev/null
[[ -f $test_home/.config/omarchy/plugins/acme.local/manifest.json ]] ||
  fail "URL plugin is not installed"
grep -Fqx 'shell discoverPlugins acme.local' "$calls" ||
  fail "URL add does not request targeted discovery"
grep -Fq 'shell enablePlugin acme.local {}' "$calls" ||
  fail "add --enable does not enable the discovered plugin"
(( $(grep -Fc 'shell discoverPlugins acme.local' "$calls") == 1 )) ||
  fail "add --enable requests explicit discovery more than once"
pass "URL add --enable discovers once and then enables the new plugin"
