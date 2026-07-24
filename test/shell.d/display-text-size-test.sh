#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

SANDBOXES=()

cleanup() {
  local sandbox
  for sandbox in "${SANDBOXES[@]}"; do
    rm -rf "$sandbox"
  done
}
trap cleanup EXIT

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  SANDBOXES+=("$SANDBOX")

  mkdir -p \
    "$SANDBOX/home/.config"/{alacritty,kitty,ghostty,foot} \
    "$SANDBOX/runtime" "$SANDBOX/bin" "$SANDBOX/log"

  cat >"$SANDBOX/bin/stub" <<SH
#!/bin/bash
name="\${0##*/}"
log_name="\$name"
[[ \$name == "gsettings" && \$1 == "get" ]] && printf '1.0\n'
[[ \$name == "omarchy-notification-send" ]] && log_name="notify"
{
  printf '%s' "\$1"
  shift
  printf ' %s' "\$@"
  printf '\n'
} >>"$SANDBOX/log/\$log_name.log"
[[ \$name == "omarchy-notification-send" ]] && printf '42\n'
exit 0
SH
  chmod +x "$SANDBOX/bin/stub"
  for name in gsettings pkill pgrep omarchy-notification-send; do
    ln -s stub "$SANDBOX/bin/$name"
  done

  printf '%s\n' "[font]" "size = 9" 'normal = { family = "Seed Alacritty" }' \
    >"$SANDBOX/home/.config/alacritty/alacritty.toml"
  printf '%s\n' "font_family Seed Kitty" "font_size 9.0" >"$SANDBOX/home/.config/kitty/kitty.conf"
  printf '%s\n' "font-family = Seed Ghostty" "font-size = 9" >"$SANDBOX/home/.config/ghostty/config"
  printf '%s\n' "[main]" "font=monospace:size=9" "pad=1x1" >"$SANDBOX/home/.config/foot/foot.ini"
}

seed_terminal_size() {
  local size="$1"
  sed -i "s/size = 9/size = $size/" "$SANDBOX/home/.config/alacritty/alacritty.toml"
  sed -i "s/font_size 9.0/font_size $size.0/" "$SANDBOX/home/.config/kitty/kitty.conf"
  sed -i "s/font-size = 9/font-size = $size/" "$SANDBOX/home/.config/ghostty/config"
  sed -i "s/:size=9/:size=$size/" "$SANDBOX/home/.config/foot/foot.ini"
}

snapshot_configs() {
  cp -r "$SANDBOX/home/.config" "$SANDBOX/before"
}

run_cli() {
  STATUS=0
  HOME="$SANDBOX/home" \
  XDG_RUNTIME_DIR="$SANDBOX/runtime" \
  PATH="$SANDBOX/bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-display-text-size" "$@" \
    >"$SANDBOX/stdout" 2>"$SANDBOX/stderr" || STATUS=$?
  OUT=$(<"$SANDBOX/stdout")
  ERR=$(<"$SANDBOX/stderr")
}

assert_file_line() {
  local relative="$1"
  local expected="$2"
  local description="$3"
  local path="$SANDBOX/home/.config/$relative"
  grep -Fqx -- "$expected" "$path" ||
    fail "$description" "missing line: $expected"$'\n'"file: $path"
}

assert_log() {
  local name="$1"
  local expected="$2"
  local description="$3"
  local actual=""
  [[ -f $SANDBOX/log/$name.log ]] && actual=$(<"$SANDBOX/log/$name.log")
  [[ $actual == $expected ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
}

assert_terminal_configs_unchanged() {
  local description="$1"
  local relative
  for relative in alacritty/alacritty.toml kitty/kitty.conf ghostty/config foot/foot.ini; do
    cmp -s "$SANDBOX/before/$relative" "$SANDBOX/home/.config/$relative" ||
      fail "$description" "changed: $relative"
  done
}

assert_terminal_sizes() {
  local size="$1"
  local description="$2"
  assert_file_line alacritty/alacritty.toml "size = $size" "$description: alacritty"
  assert_file_line kitty/kitty.conf "font_size $size.0" "$description: kitty"
  assert_file_line ghostty/config "font-size = $size" "$description: ghostty"
  assert_file_line foot/foot.ini "font=monospace:size=$size" "$description: foot"
}

assert_terminal_side_effects() {
  local description="$1"
  assert_log pkill $'-USR1 kitty\n-SIGUSR2 ghostty' "$description: reload signals"
  assert_log pgrep "-x foot" "$description: foot process check"
  assert_log notify "Restart Foot to apply the new terminal font size -p" "$description: foot notification"
}

assert_no_terminal_side_effects() {
  local description="$1"
  local name
  for name in pkill pgrep notify; do
    [[ ! -s $SANDBOX/log/$name.log ]] ||
      fail "$description: no $name invocation" "$(<"$SANDBOX/log/$name.log")"
  done
}

assert_gtk_untouched() {
  [[ ! -s $SANDBOX/log/gsettings.log ]] ||
    fail "$1" "$(<"$SANDBOX/log/gsettings.log")"
}

assert_configs_unchanged() {
  local description="$1"
  local differences=""
  differences=$(diff -r "$SANDBOX/before" "$SANDBOX/home/.config") ||
    fail "$description" "$differences"
}

assert_sandbox_untouched() {
  local description="$1"
  assert_configs_unchanged "$description: configs unchanged"
  [[ -z $(find "$SANDBOX/log" -type f -size +0c -print -quit) ]] ||
    fail "$description: stub logs empty"
}

# 1. Unflagged status reports the whole-picture state.
setup_sandbox
sed -i "s/font-size = 9/font-size = 10/" "$SANDBOX/home/.config/ghostty/config"
run_cli
((STATUS == 0)) || fail "case 1 status exits successfully" "actual: $STATUS"
[[ -z $ERR ]] || fail "case 1 status has empty stderr" "actual: $ERR"
[[ $OUT == *"text size: 12 (default) px"* ]] ||
  fail "case 1 reports the default shell size" "actual: $OUT"
[[ $OUT == *"gtk text-scaling-factor: 1.0"* ]] ||
  fail "case 1 reports the GTK factor" "actual: $OUT"
[[ $OUT == *"terminal font: 10 pt"* ]] ||
  fail "case 1 reads the Ghostty size first" "actual: $OUT"
assert_log gsettings "get org.gnome.desktop.interface text-scaling-factor" "case 1 uses the gsettings read path"

setup_sandbox
rm -r "$SANDBOX/home/.config"/{alacritty,kitty,ghostty,foot}
run_cli
((STATUS == 0)) || fail "case 1 status without terminals exits successfully" "actual: $STATUS"
[[ -z $ERR ]] || fail "case 1 status without terminals has empty stderr" "actual: $ERR"
[[ $OUT == *"terminal font: n/a pt"* ]] ||
  fail "case 1 reports no terminal config" "actual: $OUT"
pass "case 1: unflagged status reports the current whole-picture state"

# 2. Unflagged set updates every surface.
setup_sandbox
run_cli 16
((STATUS == 0)) || fail "case 2 unflagged set exits successfully" "actual: $STATUS"
[[ -z $ERR ]] || fail "case 2 unflagged set has empty stderr" "actual: $ERR"
assert_file_line omarchy/shell.toml "[font]" "case 2 creates the shell font section"
assert_file_line omarchy/shell.toml "base-size = 16" "case 2 sets the shell size"
assert_log gsettings "set org.gnome.desktop.interface text-scaling-factor 1.3333" "case 2 sets the GTK factor"
assert_terminal_sizes 12 "case 2 sets terminal sizes"
assert_file_line alacritty/alacritty.toml 'normal = { family = "Seed Alacritty" }' "case 2 preserves the Alacritty family"
assert_file_line kitty/kitty.conf "font_family Seed Kitty" "case 2 preserves the Kitty family"
assert_file_line ghostty/config "font-family = Seed Ghostty" "case 2 preserves the Ghostty family"
assert_file_line foot/foot.ini "pad=1x1" "case 2 preserves the Foot padding"
assert_terminal_side_effects "case 2"
pass "case 2: unflagged set updates every surface and reloads terminals"

# 3. Unflagged reset returns every surface to its default.
setup_sandbox
seed_terminal_size 12
mkdir -p "$SANDBOX/home/.config/omarchy"
printf '%s\n' "[font]" "base-size = 16" "" "[bar]" 'position = "top"' \
  >"$SANDBOX/home/.config/omarchy/shell.toml"
run_cli reset
((STATUS == 0)) || fail "case 3 unflagged reset exits successfully" "actual: $STATUS"
! grep -Fq -- "base-size" "$SANDBOX/home/.config/omarchy/shell.toml" ||
  fail "case 3 removes the shell base-size override"
assert_file_line omarchy/shell.toml 'position = "top"' "case 3 preserves unrelated shell settings"
assert_log gsettings "reset org.gnome.desktop.interface text-scaling-factor" "case 3 resets the GTK factor"
assert_terminal_sizes 9 "case 3 resets terminal sizes"
pass "case 3: unflagged reset returns every surface to its default"

# 4. Shell-only set leaves GTK and terminal state untouched.
setup_sandbox
snapshot_configs
run_cli --shell 16
((STATUS == 0)) || fail "case 4 shell-only set exits successfully" "actual: $STATUS"
assert_file_line omarchy/shell.toml "base-size = 16" "case 4 sets the shell size"
assert_terminal_configs_unchanged "case 4 leaves terminal configs byte-identical"
assert_gtk_untouched "case 4 does not invoke gsettings"
assert_no_terminal_side_effects "case 4"
pass "case 4: --shell updates only the shell"

# 5. GTK-only set leaves shell and terminal files untouched.
setup_sandbox
snapshot_configs
run_cli --gtk 16
((STATUS == 0)) || fail "case 5 GTK-only set exits successfully" "actual: $STATUS"
assert_log gsettings "set org.gnome.desktop.interface text-scaling-factor 1.3333" "case 5 sets the GTK factor"
assert_configs_unchanged "case 5 leaves unscoped files byte-identical"
assert_no_terminal_side_effects "case 5"
pass "case 5: --gtk updates only GTK"

# 6. Terminal-only set leaves shell and GTK untouched.
setup_sandbox
mkdir -p "$SANDBOX/home/.config/omarchy"
printf '%s\n' "[bar]" 'position = "top"' \
  >"$SANDBOX/home/.config/omarchy/shell.toml"
cp "$SANDBOX/home/.config/omarchy/shell.toml" "$SANDBOX/shell-before"
run_cli --terminals 16
((STATUS == 0)) || fail "case 6 terminal-only set exits successfully" "actual: $STATUS"
assert_terminal_sizes 12 "case 6 sets terminal sizes"
assert_terminal_side_effects "case 6"
cmp -s "$SANDBOX/shell-before" "$SANDBOX/home/.config/omarchy/shell.toml" ||
  fail "case 6 leaves shell.toml byte-identical"
assert_gtk_untouched "case 6 does not invoke gsettings"
pass "case 6: --terminals updates only terminal configs"

# 7. Two flags compose while leaving GTK untouched.
setup_sandbox
run_cli --shell --terminals 14
((STATUS == 0)) || fail "case 7 two-scope set exits successfully" "actual: $STATUS"
assert_file_line omarchy/shell.toml "base-size = 14" "case 7 sets the shell size"
assert_terminal_sizes 11 "case 7 sets mapped terminal sizes"
assert_gtk_untouched "case 7 does not invoke gsettings"
pass "case 7: --shell and --terminals compose"

# 8. GTK reset and default are both isolated.
for action in reset default; do
  setup_sandbox
  seed_terminal_size 12
  mkdir -p "$SANDBOX/home/.config/omarchy"
  printf '%s\n' "[font]" "base-size = 16" \
    >"$SANDBOX/home/.config/omarchy/shell.toml"
  snapshot_configs
  run_cli --gtk "$action"
  ((STATUS == 0)) || fail "case 8 --gtk $action exits successfully" "actual: $STATUS"
  assert_log gsettings "reset org.gnome.desktop.interface text-scaling-factor" "case 8 --gtk $action resets GTK"
  assert_configs_unchanged "case 8 --gtk $action leaves files byte-identical"
  assert_no_terminal_side_effects "case 8 --gtk $action"
done
pass "case 8: --gtk reset and default reset only GTK"

# 9. A trailing shell flag scopes reset.
setup_sandbox
seed_terminal_size 12
mkdir -p "$SANDBOX/home/.config/omarchy"
printf '%s\n' "[font]" "base-size = 16" "" "[bar]" 'position = "top"' \
  >"$SANDBOX/home/.config/omarchy/shell.toml"
snapshot_configs
run_cli reset --shell
((STATUS == 0)) || fail "case 9 trailing shell flag exits successfully" "actual: $STATUS"
! grep -Fq -- "base-size" "$SANDBOX/home/.config/omarchy/shell.toml" ||
  fail "case 9 trailing shell flag removes the shell override"
assert_file_line omarchy/shell.toml 'position = "top"' "case 9 trailing shell flag preserves unrelated shell settings"
assert_terminal_configs_unchanged "case 9 leaves terminals byte-identical"
assert_gtk_untouched "case 9 leaves GTK untouched"
assert_no_terminal_side_effects "case 9"
pass "case 9: reset --shell scopes the reset"

# 10. Help takes precedence and never mutates.
check_help() {
  setup_sandbox
  snapshot_configs
  run_cli "$@"
  ((STATUS == 0)) || fail "case 10 help exits successfully: $*" "actual: $STATUS"
  [[ -z $ERR ]] || fail "case 10 help has empty stderr: $*" "actual: $ERR"
  [[ $OUT == *"Usage:"* ]] ||
    fail "case 10 help prints usage on stdout: $*" "actual: $OUT"
  assert_sandbox_untouched "case 10 help leaves the sandbox untouched: $*"
}

check_help --shell --help
check_help 16 --help
pass "case 10: help is first and mutation-free"

# 11. Validation distinguishes size diagnostics from usage errors.
check_size_error() {
  setup_sandbox
  snapshot_configs
  run_cli "$@"
  ((STATUS == 1)) || fail "case 11 invalid size exits 1: $*" "actual: $STATUS"
  [[ -z $OUT ]] || fail "case 11 invalid size has empty stdout: $*" "actual: $OUT"
  [[ $ERR == *"Size must be an integer between 9 and 20 (px)."* ]] ||
    fail "case 11 invalid size prints the size diagnostic: $*" "actual: $ERR"
  [[ $ERR == *"Usage:"* ]] ||
    fail "case 11 invalid size prints usage: $*" "actual: $ERR"
  assert_sandbox_untouched "case 11 invalid size leaves the sandbox untouched: $*"
}

check_usage_error() {
  setup_sandbox
  snapshot_configs
  run_cli "$@"
  ((STATUS == 1)) || fail "case 11 usage error exits 1: $*" "actual: $STATUS"
  [[ -z $OUT ]] || fail "case 11 usage error has empty stdout: $*" "actual: $OUT"
  [[ $ERR == *"Usage:"* ]] ||
    fail "case 11 usage error prints usage: $*" "actual: $ERR"
  [[ $ERR != *"Size must be an integer between 9 and 20 (px)."* ]] ||
    fail "case 11 usage error omits the size diagnostic: $*" "actual: $ERR"
  assert_sandbox_untouched "case 11 usage error leaves the sandbox untouched: $*"
}

for size in 8 21 16.5 -1 08 １６ 18446744073709551625; do
  check_size_error "$size"
done
check_usage_error --bogus 16
check_usage_error --shell
check_usage_error 16 foo
pass "case 11: invalid argv fails before mutation with the right diagnostic"
