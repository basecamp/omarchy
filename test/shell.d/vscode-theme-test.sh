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
[[ ! -e $TEST_HOME/cursor-shim-called ]] || fail "VS Code theme sync ignores a PATH-provided Cursor Agent shim"
[[ ! -e $TEST_HOME/.config/Cursor/User/settings.json ]] || fail "VS Code theme sync skips Cursor when the packaged executable is unavailable"
pass "VS Code theme sync selects the packaged Cursor executable"

# A theme can ship a descriptor that names no usable 3rd-party theme. The
# generated local theme is the only fallback VS Code-family editors can
# discover, so an empty name must not be mistaken for "descriptor present,
# nothing further to do".
GENERATED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$GENERATED_HOME"' EXIT

CODIUM_HOME="$GENERATED_HOME/home"
CODIUM_BIN="$GENERATED_HOME/bin"
CODIUM_CURRENT_THEME="$CODIUM_HOME/.local/state/omarchy/current/theme"
mkdir -p "$CODIUM_BIN" "$CODIUM_CURRENT_THEME"

cat >"$CODIUM_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == codium ]]
EOF

cat >"$CODIUM_BIN/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$CODIUM_BIN/codium" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$CODIUM_BIN"/*
printf '{"name":"","extension":""}\n' >"$CODIUM_CURRENT_THEME/vscode.json"
printf '{"name":"Omarchy","type":"dark","colors":{}}\n' >"$CODIUM_CURRENT_THEME/vscode-theme.json"

PATH="$CODIUM_BIN:$ROOT/bin:$PATH" HOME="$CODIUM_HOME" "$ROOT/bin/omarchy-theme-set-vscode"

GENERATED_SETTINGS="$CODIUM_HOME/.config/VSCodium/User/settings.json"
[[ -e $GENERATED_SETTINGS ]] || fail "VS Code theme sync writes settings when no preferred theme is named"
grep -Fq '"workbench.colorTheme": "Omarchy"' "$GENERATED_SETTINGS" ||
  fail "VS Code theme sync falls back to the generated theme when the descriptor names none"
[[ -e $CODIUM_HOME/.vscode-oss/extensions/omarchy-theme/themes/omarchy-color-theme.json ]] ||
  fail "VS Code theme sync installs the generated local theme extension"
pass "VS Code theme sync falls back to the generated theme when no preferred theme is named"
