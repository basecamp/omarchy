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

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  pass "no Wayland compositor; skipping shell runtime smoke test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping shell runtime smoke test"
  exit 0
fi

require_command jq

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q "$@"
}

fail_with_log() {
  local description="$1"
  sed -n '1,240p' "$log" >&2
  fail "$description"
}

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
stub_bin="$TMPDIR/bin"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home" "$stub_bin"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

cat >"$stub_bin/omarchy-update-available" <<'SH'
#!/bin/bash
echo "Omarchy update available (test)"
exit 0
SH
chmod +x "$stub_bin/omarchy-update-available"

cat >"$test_root/shell/plugins/panels/weather/status.sh" <<'SH'
#!/bin/bash
printf '{"text":"72F","class":"sunny"}\n'
SH
chmod +x "$test_root/shell/plugins/panels/weather/status.sh"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if shell_ipc_quiet shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before IPC became available"
  fi
  sleep 0.1
done

plugins=""
for _ in {1..80}; do
  plugins=$(shell_ipc shell listPlugins 2>/dev/null || true)
  if jq -e 'length > 0' <<<"$plugins" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before plugins were listed"
  fi
  sleep 0.1
done

jq -e '
  map(.id) as $ids |
  all(["omarchy.menu", "omarchy.settings", "omarchy.notifications", "omarchy.clock"][]; $ids | index(.)) and
  all(.[]; (.kinds | type == "array") and (.enabled | type == "boolean") and (.firstParty | type == "boolean"))
' <<<"$plugins" >/dev/null || {
  printf 'Plugins:\n%s\n' "$plugins" | jq . >&2
  fail_with_log "shell IPC lists plugin metadata"
}
pass "shell IPC lists plugin metadata"

shell_config=$(shell_ipc shell listShellConfig)
jq -e '
  .version == 1 and
  (.bar.layout.left | type == "array") and
  (.bar.layout.center | type == "array") and
  (.bar.layout.right | type == "array")
' <<<"$shell_config" >/dev/null || {
  printf 'Shell config:\n%s\n' "$shell_config" | jq . >&2
  fail_with_log "shell IPC returns effective shell config"
}
pass "shell IPC returns effective shell config"

[[ $(shell_ipc shell summon omarchy.settings "{}") == "ok" ]] || fail_with_log "shell IPC summons settings panel"
shell_ipc_quiet shell hide omarchy.settings >/dev/null
[[ $(shell_ipc shell summon omarchy.launcher '{"query":"term"}') == "ok" ]] || fail_with_log "shell IPC summons launcher overlay"
shell_ipc_quiet shell hide omarchy.launcher >/dev/null
[[ $(shell_ipc shell summon missing.plugin "{}") == "unknown" ]] || fail_with_log "shell IPC rejects unknown plugin"
pass "shell IPC summon and hide contract works"

[[ $(shell_ipc notifications ping) == "ok" ]] || fail_with_log "notifications IPC responds"
[[ $(shell_ipc notifications setDnd false) == "off" ]] || fail_with_log "notifications IPC toggles DND"
[[ $(shell_ipc media ping) == "ok" ]] || fail_with_log "media IPC responds"
jq -e '.hasPlayer | type == "boolean"' <<<"$(shell_ipc media status)" >/dev/null || fail_with_log "media IPC returns status JSON"
jq -e '.enabled | type == "boolean"' <<<"$(shell_ipc idle status)" >/dev/null || fail_with_log "idle IPC returns status JSON"
jq -e '.locked | type == "boolean"' <<<"$(shell_ipc lock status)" >/dev/null || fail_with_log "lock IPC returns status JSON"
[[ $(shell_ipc image-selector ping) == "ok" ]] || fail_with_log "image selector IPC responds"
[[ $(shell_ipc osd ping) == "ok" ]] || fail_with_log "OSD IPC responds"
[[ $(shell_ipc osd show '{"message":"Runtime smoke","duration":0}') == "ok" ]] || fail_with_log "OSD IPC opens"
[[ $(shell_ipc osd close) == "ok" ]] || fail_with_log "OSD IPC closes"
pass "plugin IPC contracts respond"

shell_ipc_quiet omarchy.system-update refresh >/dev/null 2>&1 || true
sleep 0.8

default_ids=$(jq -c '(.bar.layout.left + .bar.layout.center + .bar.layout.right) | map(.id // .)' "$ROOT/config/omarchy/shell.json")
visible_default_ids='[
  "omarchy.menu",
  "omarchy.workspaces",
  "omarchy.clock",
  "omarchy.weather",
  "omarchy.system-update",
  "omarchy.indicators",
  "omarchy.network",
  "omarchy.audio",
  "omarchy.monitor"
]'

geometry=""
for _ in {1..80}; do
  geometry=$(shell_ipc shell debugBarGeometry 2>/dev/null || true)
  if jq -e --argjson expected "$default_ids" '
    . as $rows | all($expected[]; . as $id | any($rows[]; .id == $id))
  ' <<<"$geometry" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before default bar geometry settled"
  fi
  sleep 0.1
done

if [[ -z $geometry ]]; then
  fail_with_log "debug bar geometry returned output"
fi

jq -e --argjson expected "$default_ids" --argjson visibleExpected "$visible_default_ids" '
  . as $rows |
  all($expected[]; . as $id | any($rows[]; .id == $id)) and
  all($visibleExpected[]; . as $id | any($rows[]; .id == $id and .visible == true and .width > 0 and .height > 0))
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "default bar layout renders expected module slots"
}
pass "default bar layout renders expected module slots"

jq -e '
  map(select(.section == "center" and .visible == true and .width > 0)) | map(.id) as $center |
  ($center | index("omarchy.weather")) != null and
  ($center | index("omarchy.system-update")) != null and
  ($center | index("omarchy.indicators")) != null and
  (($center | index("omarchy.weather")) < ($center | index("omarchy.system-update"))) and
  (($center | index("omarchy.system-update")) < ($center | index("omarchy.indicators")))
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "runtime geometry places visible update between weather and indicators"
}

pass "runtime geometry places visible update between weather and indicators"
