#!/bin/bash

source "$(dirname "$0")/base-test.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

FAKE_BIN="$TEST_HOME/bin"
CURRENT_THEME="$TEST_HOME/.local/state/omarchy/current/theme"
mkdir -p "$FAKE_BIN" "$CURRENT_THEME"

cat >"$FAKE_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"$EDITOR_PROBE_LOG"
exit 1
EOF

cat >"$FAKE_BIN/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$FAKE_BIN/cursor" <<'EOF'
#!/bin/bash
touch "$CURSOR_SHIM_CALLED"
exit 1
EOF

chmod +x "$FAKE_BIN"/*
printf '{"name":"Hackerman","extension":"akamud.vscode-theme-onedark"}\n' >"$CURRENT_THEME/vscode.json"

EDITOR_PROBE_LOG="$TEST_HOME/editor-probes.log" \
  CURSOR_SHIM_CALLED="$TEST_HOME/cursor-shim-called" \
  PATH="$FAKE_BIN:$ROOT/bin:$PATH" \
  HOME="$TEST_HOME" \
  "$ROOT/bin/omarchy-theme-set-vscode"

grep -Fxq '/usr/bin/cursor' "$TEST_HOME/editor-probes.log" || fail "VS Code theme sync probes the packaged Cursor executable"
grep -Fxq 'positron' "$TEST_HOME/editor-probes.log" || fail "VS Code theme sync probes Positron"
[[ ! -e $TEST_HOME/cursor-shim-called ]] || fail "VS Code theme sync ignores a PATH-provided Cursor Agent shim"
[[ ! -e $TEST_HOME/.config/Cursor/User/settings.json ]] || fail "VS Code theme sync skips Cursor when the packaged executable is unavailable"
pass "VS Code theme sync selects the packaged Cursor executable"
pass "VS Code theme sync probes Positron"

cat >"$FAKE_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == "positron" ]]
EOF
rm -f "$CURRENT_THEME/vscode.json"
printf '{"type":"light"}\n' >"$CURRENT_THEME/vscode-theme.json"

PATH="$FAKE_BIN:$ROOT/bin:$PATH" \
  HOME="$TEST_HOME" \
  "$ROOT/bin/omarchy-theme-set-vscode"

grep -Fq '"workbench.colorTheme": "Omarchy"' "$TEST_HOME/.config/Positron/User/settings.json" || fail "VS Code theme sync writes Positron settings"
[[ -L $TEST_HOME/.positron/extensions/omarchy-theme/themes/omarchy-color-theme.json ]] || fail "VS Code theme sync installs the generated Positron extension"
pass "VS Code theme sync uses Positron settings and extension paths"

cat >"$FAKE_BIN/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
[[ $1 == "skip-positron-theme-changes" ]]
EOF
rm -rf "$TEST_HOME/.config/Positron" "$TEST_HOME/.positron"

PATH="$FAKE_BIN:$ROOT/bin:$PATH" \
  HOME="$TEST_HOME" \
  "$ROOT/bin/omarchy-theme-set-vscode"

[[ ! -e $TEST_HOME/.config/Positron/User/settings.json ]] || fail "VS Code theme sync honors the Positron skip toggle"
[[ ! -e $TEST_HOME/.positron/extensions/omarchy-theme ]] || fail "VS Code theme sync honors the Positron skip toggle"
pass "VS Code theme sync honors the Positron skip toggle"
