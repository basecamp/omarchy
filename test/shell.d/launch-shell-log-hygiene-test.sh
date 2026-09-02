#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

LAUNCHER="$ROOT/bin/omarchy-launch-shell"

# Quickshell's detailed instance log has no cap or rotation and ignores log
# rules for quickshell.* categories, so a long session fills the runtime dir
# tmpfs. The launcher must opt out of it; the journal keeps the trail.
if ! grep -q -- '--no-detailed-logs' "$LAUNCHER"; then
  fail "launcher passes --no-detailed-logs to quickshell"
fi
pass "launcher passes --no-detailed-logs to quickshell"

# The reap must remove dead instances of this shell's config and nothing
# else: not live instances, not other configs' instances dead or alive.
# Exercise the real launcher against a mocked quickshell and runtime dir.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

mkdir -p "$workdir/bin" "$workdir/omarchy/shell" "$workdir/fixtures"
mkdir -p "$workdir/run/quickshell/by-id"/{deadone,deadtwo,liveother,deadother}
touch "$workdir/omarchy/shell/shell.qml"
touch "$workdir/run/quickshell/by-id"/{deadone,deadtwo,liveother,deadother}/log.qslog

ours="$workdir/omarchy/shell/shell.qml"

cat > "$workdir/fixtures/alive.json" <<JSON
[
  {"config_path": "/elsewhere/shell.qml", "id": "liveother", "pid": 4242}
]
JSON

cat > "$workdir/fixtures/all.json" <<JSON
[
  {"config_path": "/elsewhere/shell.qml", "id": "liveother", "pid": 4242},
  {"config_path": "$ours", "id": "deadone", "pid": 4243},
  {"config_path": "$ours", "id": "deadtwo", "pid": 4244},
  {"config_path": "/elsewhere/shell.qml", "id": "deadother", "pid": 4245}
]
JSON

cat > "$workdir/bin/quickshell" <<MOCK
#!/bin/bash
if [[ \$1 == "list" ]]; then
  if [[ " \$* " == *" --show-dead "* ]]; then
    cat "$workdir/fixtures/all.json"
  else
    cat "$workdir/fixtures/alive.json"
  fi
fi
exit 0
MOCK

cat > "$workdir/bin/systemd-cat" <<'MOCK'
#!/bin/bash
while [[ $1 != "--" ]]; do shift; done
shift
exec "$@"
MOCK

cat > "$workdir/bin/hyprctl" <<'MOCK'
#!/bin/bash
exit 0
MOCK

chmod +x "$workdir/bin"/{quickshell,systemd-cat,hyprctl}

if ! PATH="$workdir/bin:$PATH" XDG_RUNTIME_DIR="$workdir/run" OMARCHY_PATH="$workdir/omarchy" \
  timeout 10 bash "$LAUNCHER" >/dev/null 2>&1; then
  fail "launcher exits cleanly when the mocked shell exits cleanly"
fi
pass "launcher exits cleanly when the mocked shell exits cleanly"

by_id="$workdir/run/quickshell/by-id"

[[ ! -d $by_id/deadone && ! -d $by_id/deadtwo ]] ||
  fail "dead instances of this shell's config are reaped before launch"
pass "dead instances of this shell's config are reaped before launch"

[[ -d $by_id/liveother ]] || fail "live instances are preserved"
pass "live instances are preserved"

[[ -d $by_id/deadother ]] || fail "other configs' dead instances are preserved"
pass "other configs' dead instances are preserved"
