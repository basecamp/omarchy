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

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping agents accounts test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
config_dir="$TMPDIR/agents-accounts"
usage_dir="$TMPDIR/state/omarchy/agents/usage"
mkdir -p "$config_dir" "$TMPDIR/home" "$TMPDIR/bin" "$usage_dir"
cp "$SHELL_TEST_DIR/fixtures/agents-accounts/shell.qml" "$config_dir/shell.qml"

# Two accounts of one tool, the way collectors.d wrappers would write them.
cat >"$usage_dir/claude.json" <<'EOF'
{"schemaVersion":1,"id":"claude","name":"Claude Code","mark":"claude","ready":true,"totalPrompts":3}
EOF
cat >"$usage_dir/claude-work.json" <<'EOF'
{"schemaVersion":1,"id":"claude-work","name":"Work","mark":"claude","ready":true,"totalPrompts":5}
EOF

# Main.qml runs the updater once at startup; a stub keeps that run away from
# the real collectors and the fixture records they would overwrite.
cat >"$TMPDIR/bin/omarchy-agent-usage-update" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMPDIR/bin/omarchy-agent-usage-update"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$TMPDIR/state" \
PATH="$TMPDIR/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..100}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log" >&2
    fail "agents accounts quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,120p' "$log" >&2
  fail "agents accounts test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Agents accounts result:\n' >&2
  jq . "$result" >&2
  printf 'Agents accounts log:\n' >&2
  sed -n '1,120p' "$log" >&2
  fail "agents accounts identity checks pass"
fi

pass "agents accounts identity checks pass"
