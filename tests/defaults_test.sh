#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ $expected != "$actual" ]]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  grep -Fqx "$pattern" "$file" || fail "$message"
}

create_stub_commands() {
  mkdir -p "$TEST_BIN" "$HOME/.config/uwsm" "$HOME/.config" "$HOME/.local/share/applications"

  cat >"$TEST_BIN/xdg-terminal-exec" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "--print-id" ]]; then
  awk 'NF && $1 !~ /^#/' "$HOME/.config/xdg-terminals.list" | head -1
  exit 0
fi

exit 1
EOF

  cat >"$TEST_BIN/xdg-settings" <<'EOF'
#!/bin/bash
set -euo pipefail

state_file="$HOME/.config/browser.default"

case "${1:-}" in
get)
  cat "$state_file"
  ;;
set)
  printf '%s\n' "$3" >"$state_file"
  ;;
*)
  exit 1
  ;;
esac
EOF

  cat >"$TEST_BIN/xdg-mime" <<'EOF'
#!/bin/bash
set -euo pipefail

state_file="$HOME/.config/mimeapps.test"
mkdir -p "$(dirname "$state_file")"
touch "$state_file"

case "${1:-}" in
query)
  mime="${3:-}"
  awk -F= -v mime="$mime" '$1 == mime { print $2 }' "$state_file" | tail -1
  ;;
default)
  desktop_id="$2"
  shift 2
  for mime in "$@"; do
    awk -F= -v mime="$mime" '$1 != mime { print $0 }' "$state_file" >"$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
    printf '%s=%s\n' "$mime" "$desktop_id" >>"$state_file"
  done
  ;;
*)
  exit 1
  ;;
esac
EOF

  cat >"$TEST_BIN/gio" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} != "mime" ]]; then
  exit 1
fi

mime="${2:-}"
default=""
if [[ -f $HOME/.config/mimeapps.test ]]; then
  default=$(awk -F= -v mime="$mime" '$1 == mime { print $2 }' "$HOME/.config/mimeapps.test" | tail -1)
fi

registered=()
for file in "$HOME/.local/share/applications"/*.desktop; do
  [[ -f $file ]] || continue
  if sed -n 's/^MimeType=//p' "$file" | grep -q "$mime"; then
    registered+=("$(basename "$file")")
  fi
done

printf 'Default application for “%s”: %s\n' "$mime" "${default:-}"
printf 'Registered applications:\n'
for app in "${registered[@]}"; do
  printf '\t%s\n' "$app"
done
printf 'Recommended applications:\n'
for app in "${registered[@]}"; do
  printf '\t%s\n' "$app"
done
EOF

  cat >"$TEST_BIN/getent" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "passwd" ]]; then
  printf 'tester:x:1000:1000::/home/tester:%s\n' "$(cat "$HOME/.config/login.shell")"
  exit 0
fi

exit 1
EOF

  cat >"$TEST_BIN/chsh" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$2" >"$HOME/.config/login.shell"
printf '%s\n' "$*" >"$HOME/.config/chsh.log"
EOF

  cat >"$TEST_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
set -euo pipefail

command -v "$1" >/dev/null 2>&1
EOF

  cat >"$TEST_BIN/omarchy-launch-tui" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >"$HOME/.config/launch-editor.log"
EOF

  cat >"$TEST_BIN/setsid" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >"$HOME/.config/setsid.log"
EOF

  cat >"$TEST_BIN/gtk-launch" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >"$HOME/.config/gtk-launch.log"
EOF

  cat >"$TEST_BIN/hx" <<'EOF'
#!/bin/bash
exit 0
EOF

  cat >"$TEST_BIN/nvim" <<'EOF'
#!/bin/bash
exit 0
EOF

  chmod +x "$TEST_BIN"/*
}

create_desktop_file() {
  local id="$1"
  local name="$2"
  local categories="$3"
  local mimetypes="$4"

  cat >"$HOME/.local/share/applications/$id" <<EOF
[Desktop Entry]
Name=$name
Exec=${id%.desktop}
TryExec=${id%.desktop}
Type=Application
Categories=$categories
MimeType=$mimetypes
EOF
}

setup_test_env() {
  TEST_ROOT=$(mktemp -d)
  export HOME="$TEST_ROOT/home"
  export TEST_BIN="$TEST_ROOT/bin"
  export USER="tester"
  export OMARCHY_PATH="$REPO_ROOT"
  export PATH="$TEST_BIN:/usr/bin:/bin"

  mkdir -p "$HOME"

  create_stub_commands

  cat >"$HOME/.config/uwsm/default" <<'EOF'
# Changes require a restart to take effect.
export TERMINAL=xdg-terminal-exec
export EDITOR=nvim
EOF

  cat >"$HOME/.config/xdg-terminals.list" <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
Alacritty.desktop
EOF

  printf '/usr/bin/zsh\n' >"$HOME/.config/login.shell"
  printf 'chromium.desktop\n' >"$HOME/.config/browser.default"

  create_desktop_file "Alacritty.desktop" "Alacritty" "System;TerminalEmulator;" ""
  create_desktop_file "kitty.desktop" "Kitty" "System;TerminalEmulator;" ""
  create_desktop_file "chromium.desktop" "Chromium" "Network;WebBrowser;" "text/html;x-scheme-handler/http;x-scheme-handler/https;image/png;"
  create_desktop_file "brave-browser.desktop" "Brave" "Network;WebBrowser;" "text/html;x-scheme-handler/http;x-scheme-handler/https;"
  create_desktop_file "imv.desktop" "Image Viewer" "Graphics;Viewer;" "image/png;image/jpeg;image/gif;image/webp;image/bmp;image/tiff;"
  create_desktop_file "mpv.desktop" "Media Player" "AudioVideo;Player;" "video/mp4;audio/mpeg;audio/flac;audio/wav;audio/ogg;audio/opus;audio/webm;"
  create_desktop_file "nvim.desktop" "Neovim" "Utility;TextEditor;Development;" "text/plain;text/x-c;application/xml;text/xml;"
  create_desktop_file "hx.desktop" "Helix" "Utility;TextEditor;Development;" "text/plain;text/x-c;application/xml;text/xml;"
  create_desktop_file "org.gnome.Evince.desktop" "Document Viewer" "Office;Viewer;" "application/pdf;"
  create_desktop_file "org.gnome.Nautilus.desktop" "Files" "System;FileManager;" "inode/directory;"
  create_desktop_file "HEY.desktop" "HEY" "Network;" "x-scheme-handler/mailto;"
}

test_terminal_apply_updates_terminal_preference() {
  "$REPO_ROOT/bin/omarchy-defaults" apply terminal kitty.desktop

  assert_file_contains "$HOME/.config/xdg-terminals.list" "kitty.desktop" "terminal default should be persisted"
  assert_equals "kitty.desktop" "$("$REPO_ROOT/bin/omarchy-defaults" current terminal)" "current terminal should come from xdg-terminal-exec"
}

test_editor_apply_updates_uwsm_default_and_text_mimes() {
  "$REPO_ROOT/bin/omarchy-defaults" apply editor hx

  assert_file_contains "$HOME/.config/uwsm/default" "export EDITOR=hx" "editor should be written to uwsm defaults"
  assert_equals "hx.desktop" "$("$REPO_ROOT/bin/omarchy-defaults" current editor-desktop)" "editor desktop should resolve from configured editor"
  assert_equals "hx.desktop" "$(xdg-mime query default text/plain)" "text/plain should follow selected editor"
}

test_browser_apply_updates_xdg_state() {
  "$REPO_ROOT/bin/omarchy-defaults" apply browser brave-browser.desktop

  assert_equals "brave-browser.desktop" "$(xdg-settings get default-web-browser)" "browser should be stored via xdg-settings"
  assert_equals "brave-browser.desktop" "$(xdg-mime query default x-scheme-handler/http)" "http handler should follow selected browser"
}

test_pdf_apply_updates_pdf_mime() {
  "$REPO_ROOT/bin/omarchy-defaults" apply pdf org.gnome.Evince.desktop

  assert_equals "org.gnome.Evince.desktop" "$(xdg-mime query default application/pdf)" "application/pdf should follow selected viewer"
  assert_equals "org.gnome.Evince.desktop" "$("$REPO_ROOT/bin/omarchy-defaults" current pdf)" "current pdf viewer should read back through xdg-mime"
}

test_filemanager_apply_updates_directory_mime() {
  "$REPO_ROOT/bin/omarchy-defaults" apply filemanager org.gnome.Nautilus.desktop

  assert_equals "org.gnome.Nautilus.desktop" "$(xdg-mime query default inode/directory)" "inode/directory should follow selected file manager"
}

test_mail_apply_updates_mailto_handler() {
  "$REPO_ROOT/bin/omarchy-defaults" apply mail HEY.desktop

  assert_equals "HEY.desktop" "$(xdg-mime query default x-scheme-handler/mailto)" "mailto handler should follow selected mail app"
}

test_image_candidates_exclude_browsers() {
  local candidates
  candidates=$("$REPO_ROOT/bin/omarchy-defaults" list image)

  [[ $candidates == *"imv.desktop|Image Viewer"* ]] || fail "image candidates should include image viewer"
  [[ $candidates != *"chromium.desktop|Chromium"* ]] || fail "image candidates should exclude browsers"
}

test_shell_candidates_exclude_sh() {
  local candidates
  candidates=$("$REPO_ROOT/bin/omarchy-defaults" list shell)

  [[ $candidates != *"/bin/sh|Sh"* ]] || fail "shell candidates should exclude sh"
  [[ $candidates == *"/bin/bash|Bash"* ]] || fail "shell candidates should include bash"
}

test_shell_apply_invokes_chsh() {
  "$REPO_ROOT/bin/omarchy-defaults" apply shell /bin/bash

  assert_equals "/bin/bash" "$(cat "$HOME/.config/login.shell")" "shell change should flow through chsh"
}

test_reset_all_restores_defaults() {
  if "$REPO_ROOT/bin/omarchy-defaults" reset-all >/dev/null 2>&1; then
    fail "reset-all should no longer be exposed"
  fi
}

test_open_uses_expected_launcher() {
  "$REPO_ROOT/bin/omarchy-defaults" open editor hx
  assert_equals "hx" "$(cat "$HOME/.config/launch-editor.log")" "opening a TUI editor should use omarchy-launch-tui"

  "$REPO_ROOT/bin/omarchy-defaults" open browser chromium.desktop
  assert_equals "gtk-launch chromium" "$(cat "$HOME/.config/setsid.log")" "opening a browser should use gtk-launch via setsid"

  "$REPO_ROOT/bin/omarchy-defaults" open terminal Alacritty.desktop
  assert_equals "gtk-launch Alacritty" "$(cat "$HOME/.config/setsid.log")" "opening a terminal should use gtk-launch via setsid"
}

test_editor_mode_and_notes() {
  assert_equals "tui" "$("$REPO_ROOT/bin/omarchy-defaults" mode editor hx)" "terminal editors should be marked as tui"
  assert_equals "gui" "$("$REPO_ROOT/bin/omarchy-defaults" mode browser chromium.desktop)" "desktop apps should be marked as gui"
  assert_equals "requires relogin" "$("$REPO_ROOT/bin/omarchy-defaults" note shell)" "shell should expose relogin note"
  assert_equals "" "$("$REPO_ROOT/bin/omarchy-defaults" note pdf)" "pdf should not expose an extra note"
}

test_launch_editor_reads_latest_uwsm_default() {
  cat >"$HOME/.config/uwsm/default" <<'EOF'
export TERMINAL=xdg-terminal-exec
export EDITOR=hx
EOF

  "$REPO_ROOT/bin/omarchy-launch-editor" README.md

  assert_equals "hx README.md" "$(cat "$HOME/.config/launch-editor.log")" "launch editor should source uwsm defaults on every run"
}

main() {
  setup_test_env

  test_terminal_apply_updates_terminal_preference
  test_editor_apply_updates_uwsm_default_and_text_mimes
  test_browser_apply_updates_xdg_state
  test_pdf_apply_updates_pdf_mime
  test_filemanager_apply_updates_directory_mime
  test_mail_apply_updates_mailto_handler
  test_image_candidates_exclude_browsers
  test_shell_candidates_exclude_sh
  test_shell_apply_invokes_chsh
  test_reset_all_restores_defaults
  test_open_uses_expected_launcher
  test_editor_mode_and_notes
  test_launch_editor_reads_latest_uwsm_default

  echo "defaults_test.sh: ok"
}

main "$@"
