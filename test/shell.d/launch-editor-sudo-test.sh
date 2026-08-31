#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

launcher="$ROOT/bin/omarchy-launch-editor"
chooser="$ROOT/bin/omarchy-default-editor"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home="$test_tmp/home"
mkdir -p "$stub_bin" "$home/.local/state/omarchy/defaults"

# Every command the launcher can hand the file to logs its own argv, so the
# assertions read the process that would actually have run.
for stub in nvim vim nano micro hx helix fresh code cursor zeditor sublime_text \
  emacs setsid uwsm-app omarchy-launch-tui; do
  cat >"$stub_bin/$stub" <<SH
#!/bin/bash
printf '%s %s\n' "$stub" "\$*" >>"\$LAUNCH_LOG"
SH
  chmod +x "$stub_bin/$stub"
done

# Without this the launcher falls back to nvim for every editor and the run
# proves nothing about the editor that was chosen.
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-cmd-present"

launch_with() {
  local editor="$1"
  shift

  printf '%s\n' "$editor" >"$home/.local/state/omarchy/defaults/editor"
  : >"$test_tmp/log"
  LAUNCH_LOG="$test_tmp/log" HOME="$home" PATH="$stub_bin:$PATH" \
    bash "$launcher" "$@" /etc/sudoers.tmp >/dev/null 2>&1 || true
  cat "$test_tmp/log"
}

# The editors the menu can actually put in that state file, read off the
# chooser so an editor added there is covered here without a second edit.
mapfile -t editors < <(grep -oE 'editor="[a-z_]+"' "$chooser" | cut -d'"' -f2 | sort -u)
((${#editors[@]} >= 8)) ||
  fail "the chooser's editor list was read" "got: ${editors[*]}"

for editor in "${editors[@]}"; do
  launched=$(launch_with "$editor" --sudo)

  [[ $launched == *"/etc/sudoers.tmp"* ]] ||
    fail "--sudo hands $editor the file to edit" "got: $launched"

  # setsid and uwsm-app both return before the editor is done, which is what
  # loses the edit. Neither belongs anywhere on the sudo path.
  [[ $launched != *"setsid"* && $launched != *"uwsm-app"* ]] ||
    fail "--sudo does not detach the editor for $editor" "got: $launched"

  # omarchy-launch-tui opens a separate terminal window and returns, so it is
  # no better here than detaching outright.
  [[ $launched != *"omarchy-launch-tui"* ]] ||
    fail "--sudo does not hand $editor to a separate terminal" "got: $launched"
done

pass "--sudo blocks for every editor the chooser offers"

# The windowed and inline paths are unchanged: a graphical editor still gets
# detached when it is not sudo asking.
windowed=$(launch_with code)
[[ $windowed == "setsid uwsm-app -- code /etc/sudoers.tmp" ]] ||
  fail "a graphical editor is still detached when launched windowed" "got: $windowed"

windowed=$(launch_with nvim)
[[ $windowed == "omarchy-launch-tui nvim /etc/sudoers.tmp" ]] ||
  fail "a terminal editor is still opened in a terminal when launched windowed" "got: $windowed"

inline=$(launch_with nvim --inline)
[[ $inline == "nvim /etc/sudoers.tmp" ]] ||
  fail "--inline still runs a terminal editor in place" "got: $inline"

pass "the windowed and inline paths are unchanged"
