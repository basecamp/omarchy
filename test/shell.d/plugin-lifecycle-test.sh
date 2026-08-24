#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
test_home="$TMPDIR/home"
stub_dir="$TMPDIR/bin"
calls="$TMPDIR/calls"
mkdir -p "$test_home/.config/omarchy/plugins" "$stub_dir"

cat >"$stub_dir/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ ${1:-} == shell && ${2:-} == listPlugins ]]; then
  printf '%s\n' "${OMARCHY_TEST_PLUGINS:-[]}"
elif [[ ${1:-} == shell && ${2:-} == setPluginEnabled ]]; then
  printf 'ok\n'
fi
SH
chmod +x "$stub_dir/omarchy-shell"

write_version() {
  local dir="$1"
  local version="$2"
  jq -n --arg version "$version" '{
    schemaVersion: 1,
    id: "acme.lifecycle",
    name: "Lifecycle",
    version: $version,
    kinds: ["service"],
    entryPoints: {service: "Service.qml"}
  }' >"$dir/manifest.json"
  printf 'import QtQuick\nItem { property string version: "%s" }\n' "$version" >"$dir/Service.qml"
}

upstream="$TMPDIR/upstream"
mkdir -p "$upstream"
git -C "$upstream" init -q
write_version "$upstream" 1
git -C "$upstream" add .
git -C "$upstream" -c user.name=Test -c user.email=test@example.com commit -qm v1
git clone -q "$upstream" "$test_home/.config/omarchy/plugins/acme.lifecycle"
write_version "$upstream" 2
git -C "$upstream" add .
git -C "$upstream" -c user.name=Test -c user.email=test@example.com commit -qm v2

HOME="$test_home" OMARCHY_PATH="$ROOT" OMARCHY_TEST_CALLS="$calls" \
  PATH="$stub_dir:$ROOT/bin:$PATH" omarchy-plugin-update acme.lifecycle --yes >/dev/null
[[ $(jq -r .version "$test_home/.config/omarchy/plugins/acme.lifecycle/manifest.json") == 2 ]] ||
  fail "plugin update does not install changed plugin contents"
grep -Fqx 'shell rescanPlugins' "$calls" ||
  fail "plugin update does not request full reload semantics"
! grep -q 'discoverPlugins' "$calls" ||
  fail "plugin update is mistaken for new-plugin discovery"
pass "plugin update retains full reload semantics for changed contents"

: >"$calls"
plugins='[{"id":"acme.lifecycle","enabled":true}]'
HOME="$test_home" OMARCHY_PATH="$ROOT" OMARCHY_TEST_CALLS="$calls" \
  OMARCHY_TEST_PLUGINS="$plugins" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-remove acme.lifecycle --yes >/dev/null
[[ ! -e $test_home/.config/omarchy/plugins/acme.lifecycle ]] ||
  fail "plugin remove leaves its git checkout installed"
grep -Fqx 'shell setPluginEnabled acme.lifecycle false' "$calls" ||
  fail "plugin remove does not disable a loaded plugin first"
grep -Fqx 'shell rescanPlugins' "$calls" ||
  fail "plugin remove does not retain full reload semantics"
pass "plugin remove disables its plugin and retains the existing full reload path"
