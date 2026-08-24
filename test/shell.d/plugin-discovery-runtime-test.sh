#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

require_compositor "plugin discovery runtime test"
command -v quickshell >/dev/null 2>&1 || {
  pass "quickshell not installed; skipping plugin discovery runtime test"
  exit 0
}
require_command jq

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
plugins_dir="$test_home/.config/omarchy/plugins"
log="$TMPDIR/quickshell.log"
stub_dir="$TMPDIR/bin"
scan_arm="$TMPDIR/scan-arm"
scan_reached="$TMPDIR/scan-reached"
scan_release="$TMPDIR/scan-release"
mkdir -p "$test_root" "$plugins_dir" "$stub_dir"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

cat >"$stub_dir/bash" <<'SH'
#!/bin/bash
if [[ -e $OMARCHY_TEST_SCAN_ARM && ${2:-} == *scan_firstparty* ]]; then
  rm "$OMARCHY_TEST_SCAN_ARM"
  output=$(/bin/bash "$@")
  : >"$OMARCHY_TEST_SCAN_REACHED"
  while [[ ! -e $OMARCHY_TEST_SCAN_RELEASE ]]; do sleep 0.01; done
  printf '%s\n' "$output"
else
  exec /bin/bash "$@"
fi
SH
chmod +x "$stub_dir/bash"

write_service() {
  local dir="$1"
  local id="$2"
  local version="$3"
  mkdir -p "$dir"
  jq -n --arg id "$id" --arg version "$version" '{
    schemaVersion: 1,
    id: $id,
    name: $id,
    version: $version,
    kinds: ["service"],
    entryPoints: {service: "Service.qml"}
  }' >"$dir/manifest.json"
  cat >"$dir/Service.qml" <<QML
import QtQuick

Item {
  property var shell: null
  property var manifest: null
  Component.onCompleted: console.log("PLUGIN_DISCOVERY_TEST_INSTANCE", "$id", "$version")
}
QML
}

write_service "$plugins_dir/test.service-a" test.service-a 1
write_service "$plugins_dir/test.service-b" test.service-b 1
mkdir -p "$test_home/.config/omarchy"
jq '.plugins = [{id: "test.service-a"}, {id: "test.service-b"}]' \
  "$ROOT/config/omarchy/shell.json" >"$test_home/.config/omarchy/shell.json"

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

fail_with_log() {
  local description="$1"
  sed -n '1,240p' "$log" >&2
  fail "$description"
}

instance_count() {
  grep -c "PLUGIN_DISCOVERY_TEST_INSTANCE $1 $2" "$log" 2>/dev/null || true
}

wait_for_count() {
  local id="$1"
  local version="$2"
  local expected="$3"
  for _ in {1..80}; do
    (( $(instance_count "$id" "$version") >= expected )) && return 0
    kill -0 "$QS_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

wait_for_plugin() {
  local id="$1"
  local expected="$2"
  for _ in {1..80}; do
    local present=0
    shell_ipc shell listPlugins 2>/dev/null |
      jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && present=1
    (( present == expected )) && return 0
    kill -0 "$QS_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

wait_for_log() {
  local pattern="$1"
  for _ in {1..80}; do
    grep -qF "$pattern" "$log" 2>/dev/null && return 0
    kill -0 "$QS_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

start_blocked_scan() {
  local name="$1"
  rm -f "$scan_reached" "$scan_release"
  : >"$scan_arm"
  write_service "$plugins_dir/.add.block-$name" "test.scan-block-$name" 1
  mv "$plugins_dir/.add.block-$name" "$plugins_dir/test.scan-block-$name"
  for _ in {1..80}; do
    [[ -e $scan_reached ]] && return 0
    kill -0 "$QS_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

release_blocked_scan() {
  : >"$scan_release"
}

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
OMARCHY_TEST_SCAN_ARM="$scan_arm" \
OMARCHY_TEST_SCAN_REACHED="$scan_reached" \
OMARCHY_TEST_SCAN_RELEASE="$scan_release" \
PATH="$stub_dir:$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  shell_ipc shell ping >/dev/null 2>&1 && break
  kill -0 "$QS_PID" 2>/dev/null || fail_with_log "test shell exited before IPC became available"
  sleep 0.1
done
wait_for_count test.service-a 1 1 || fail_with_log "existing service A starts once"
wait_for_count test.service-b 1 1 || fail_with_log "existing service B starts once"

# Installation uses a hidden completed staging directory followed by one final
# rename, matching omarchy-plugin-add. Explicit discovery may race the watcher.
write_service "$plugins_dir/.add.test" test.service-c 1
mv "$plugins_dir/.add.test" "$plugins_dir/test.service-c"
shell_ipc shell discoverPlugins test.service-c >/dev/null
wait_for_plugin test.service-c 1 || fail_with_log "new service is discovered"
(( $(instance_count test.service-a 1) == 1 && $(instance_count test.service-b 1) == 1 )) ||
  fail_with_log "discovering a new plugin does not recreate existing services"
(( $(instance_count test.service-c 1) == 0 )) ||
  fail_with_log "a newly discovered disabled service is not instantiated"
pass "new disabled plugins are discovered without recreating existing services"

[[ $(shell_ipc shell setPluginEnabled test.service-c true) == ok ]] ||
  fail_with_log "new service can be enabled after discovery"
wait_for_count test.service-c 1 1 || fail_with_log "new service is instantiated after enable"
(( $(instance_count test.service-a 1) == 1 && $(instance_count test.service-b 1) == 1 )) ||
  fail_with_log "enabling the new service does not recreate existing services"
(( $(instance_count test.service-c 1) == 1 )) ||
  fail_with_log "new service is instantiated exactly once"
pass "enabling a discovered service creates only that service once"

# Block a scan after its third-party directory glob has been expanded. Plugins
# moved into place now cannot be part of that scan, so only a queued follow-up
# can discover them.
start_blocked_scan watcher-first || fail_with_log "watcher-first scan reaches its deterministic hold point"
write_service "$plugins_dir/.add.test" test.service-watcher-first 1
mv "$plugins_dir/.add.test" "$plugins_dir/test.service-watcher-first"
wait_for_log "Local plugin added, discovering: test.service-watcher-first" ||
  fail_with_log "watcher requests discovery while the registry is scanning"
shell_ipc shell discoverPlugins test.service-watcher-first >/dev/null
if shell_ipc shell listPlugins | jq -e 'any(.[]; .id == "test.service-watcher-first")' >/dev/null; then
  fail_with_log "blocked initial scan discovers a plugin added after enumeration"
fi
release_blocked_scan watcher-first
wait_for_plugin test.service-watcher-first 1 || fail_with_log "watcher-first pending discovery is processed"
[[ $(shell_ipc shell setPluginEnabled test.service-watcher-first true) == ok ]] ||
  fail_with_log "watcher-first service can be enabled"
wait_for_count test.service-watcher-first 1 1 || fail_with_log "watcher-first service is instantiated"
(( $(instance_count test.service-watcher-first 1) == 1 )) ||
  fail_with_log "watcher-first service is instantiated exactly once"
(( $(instance_count test.service-a 1) == 1 && $(instance_count test.service-b 1) == 1 )) ||
  fail_with_log "watcher-first queued discovery does not recreate existing services"
pass "watcher-first discovery queued during a scan is not lost"

start_blocked_scan ipc-first || fail_with_log "IPC-first scan reaches its deterministic hold point"
shell_ipc shell discoverPlugins test.service-ipc-first >/dev/null
write_service "$plugins_dir/.add.test" test.service-ipc-first 1
mv "$plugins_dir/.add.test" "$plugins_dir/test.service-ipc-first"
wait_for_log "Local plugin added, discovering: test.service-ipc-first" ||
  fail_with_log "watcher acknowledges IPC-first discovery while the registry is scanning"
if shell_ipc shell listPlugins | jq -e 'any(.[]; .id == "test.service-ipc-first")' >/dev/null; then
  fail_with_log "blocked initial scan discovers the IPC-first plugin added after enumeration"
fi
release_blocked_scan ipc-first
wait_for_plugin test.service-ipc-first 1 || fail_with_log "IPC-first pending discovery is processed"
[[ $(shell_ipc shell setPluginEnabled test.service-ipc-first true) == ok ]] ||
  fail_with_log "IPC-first service can be enabled"
wait_for_count test.service-ipc-first 1 1 || fail_with_log "IPC-first service is instantiated"
(( $(instance_count test.service-ipc-first 1) == 1 )) ||
  fail_with_log "IPC-first service is instantiated exactly once"
(( $(instance_count test.service-a 1) == 1 && $(instance_count test.service-b 1) == 1 )) ||
  fail_with_log "IPC-first queued discovery does not recreate existing services"
pass "IPC-first discovery queued during a scan is not lost"

shell_ipc shell rescanPlugins >/dev/null
wait_for_count test.service-a 1 2 || fail_with_log "explicit rescan recreates service A"
wait_for_count test.service-b 1 2 || fail_with_log "explicit rescan recreates service B"
wait_for_count test.service-c 1 2 || fail_with_log "explicit rescan recreates service C"
pass "explicit rescanPlugins retains full code-reload semantics"

jq '.name = "Edited service B"' "$plugins_dir/test.service-b/manifest.json" >"$TMPDIR/manifest.json"
mv "$TMPDIR/manifest.json" "$plugins_dir/test.service-b/manifest.json"
wait_for_count test.service-b 1 3 || fail_with_log "known plugin edit triggers full reload"
grep -q "Local plugin changed, reloading: test.service-b" "$log" ||
  fail_with_log "known plugin edit is classified as a reload"
pass "editing an installed plugin retains live code reload"

shell_ipc shell setPluginEnabled test.service-c false >/dev/null
rm -rf "$plugins_dir/test.service-c"
shell_ipc shell rescanPlugins >/dev/null
wait_for_plugin test.service-c 0 || fail_with_log "removed plugin leaves the registry"
before_a=$(instance_count test.service-a 1)
before_b=$(instance_count test.service-b 1)
write_service "$plugins_dir/.add.test" test.service-c 2
mv "$plugins_dir/.add.test" "$plugins_dir/test.service-c"
shell_ipc shell discoverPlugins test.service-c >/dev/null
wait_for_plugin test.service-c 1 || fail_with_log "same-id plugin is rediscovered"
wait_for_count test.service-a 1 "$((before_a + 1))" || fail_with_log "same-id reinstallation reloads service A"
wait_for_count test.service-b 1 "$((before_b + 1))" || fail_with_log "same-id reinstallation reloads service B"
pass "remove and re-add of a session-known id uses full reload semantics"
