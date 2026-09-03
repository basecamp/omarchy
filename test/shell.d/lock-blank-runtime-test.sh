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
  # Qt can still be flushing its cache as the process dies, so a first pass can
  # walk a tree that grows behind it. A second one clears what landed late.
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR" 2>/dev/null || rm -rf "$TMPDIR" 2>/dev/null || true
  fi
  return 0
}
trap cleanup EXIT

require_compositor "lock blank timeout runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping lock blank timeout runtime test"
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
shell_config="$test_home/.config/omarchy/shell.json"
mkdir -p "$test_root" "$test_home/.config/omarchy" "$stub_bin"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

# The test shell shares the session's idle notifications, so keep its own idle
# deadlines out of reach and stub what an idle cycle would reach for. Nothing
# here should dim or lock the desktop running the suite.
for stubbed in omarchy-system-lock omarchy-launch-screensaver omarchy-brightness-display omarchy-brightness-keyboard; do
  cat >"$stub_bin/$stubbed" <<'SH_STUB'
#!/bin/bash
exit 0
SH_STUB
  chmod +x "$stub_bin/$stubbed"
done

write_shell_config() {
  local blank_entry="$1"

  cat >"$shell_config" <<JSON
{
  "version": 1,
  "idle": {
    "screensaver": 36000,
    "lock": 36000$blank_entry
  },
  "bar": {
    "layout": {
      "left": [],
      "center": [{ "id": "omarchy.clock" }],
      "right": []
    }
  },
  "plugins": []
}
JSON
}

blank_timeout() {
  shell_ipc lock status 2>/dev/null | jq -r '.blank // "missing"'
}

await_blank_timeout() {
  local expected="$1"
  local seen=""

  for _ in {1..80}; do
    seen=$(blank_timeout)
    [[ $seen == "$expected" ]] && return 0
    sleep 0.1
  done

  printf 'expected: %s\nactual:   %s\n' "$expected" "$seen" >&2
  return 1
}

write_shell_config ',
    "blank": 42'

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  shell_ipc_quiet shell ping >/dev/null 2>&1 && break
  kill -0 "$QS_PID" 2>/dev/null || fail_with_log "test shell exited before IPC became available"
  sleep 0.1
done

shell_ipc_quiet shell ping >/dev/null 2>&1 || fail_with_log "test shell answers IPC"

await_blank_timeout 42 || fail_with_log "lock screen adopts the configured blank timeout"
pass "lock screen adopts the configured blank timeout"

write_shell_config ',
    "blank": 9'
await_blank_timeout 9 || fail_with_log "lock screen picks up an edited blank timeout without a restart"
pass "lock screen picks up an edited blank timeout without a restart"

write_shell_config ''
await_blank_timeout 5 || fail_with_log "lock screen falls back to the five second default"
pass "lock screen falls back to the five second default"

write_shell_config ',
    "blank": "nonsense"'
await_blank_timeout 5 || fail_with_log "lock screen ignores a nonsense blank timeout"
pass "lock screen ignores a nonsense blank timeout"

# The blank timeout is read from a plugin that can lock the desktop running the
# suite. Prove the checks above never asked it to.
if grep -qE 'omarchy (lock|idle) [^ ]+ (lock-requested|lock-system)' "$log"; then
  fail_with_log "the runtime check leaves the session unlocked"
fi
pass "the runtime check leaves the session unlocked"
