#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir" "$home_dir/.local/state/omarchy/toggles"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == "activeworkspace" && $2 == "-j" ]]; then
  if [[ -n $HYPRCTL_BROKEN ]]; then
    printf '{}\n'
  else
    printf '{"id":%s}\n' "${HYPR_ACTIVE_WORKSPACE:-2}"
  fi
  exit 0
fi

if [[ $1 == "activewindow" && $2 == "-j" ]]; then
  printf '{"address":"%s","fullscreen":%s,"fullscreenClient":%s}\n' \
    "${HYPR_ADDRESS:-0x1}" \
    "${HYPR_FULLSCREEN:-0}" \
    "${HYPR_FULLSCREEN_CLIENT:-0}"
  exit 0
fi

if [[ $1 == "dispatch" ]]; then
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
  exit 0
fi

exit 1
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
[[ -f "$HOME/.local/state/omarchy/toggles/$1" ]]
EOF
chmod +x "$stub_dir/omarchy-toggle-enabled"

run_focus() {
  HOME="$home_dir" HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
    HYPR_ACTIVE_WORKSPACE="${HYPR_ACTIVE_WORKSPACE:-2}" \
    HYPR_FULLSCREEN="${HYPR_FULLSCREEN:-0}" \
    "$ROOT/bin/omarchy-hyprland-workspace-focus" "$@"
}

>"$log_file"
HYPR_ACTIVE_WORKSPACE=1 run_focus 2
grep -Fq 'hl.dsp.focus({ workspace = "2" })' "$log_file" ||
  fail "workspace focus switches when not already there"
pass "workspace focus switches when not already there"

>"$log_file"
HYPR_ACTIVE_WORKSPACE=2 HYPR_FULLSCREEN=0 run_focus 2
grep -Fq 'hl.dsp.window.fullscreen_state({ internal = 1, client = 1 })' "$log_file" ||
  fail "workspace repress enables full width when already there"
! grep -Fq 'workspace = "2"' "$log_file" ||
  fail "workspace repress does not re-dispatch workspace focus"
pass "workspace repress enables full width when already there"

>"$log_file"
HYPR_ACTIVE_WORKSPACE=2 HYPR_FULLSCREEN=1 run_focus 2
grep -Fq 'hl.dsp.window.fullscreen_state({ internal = 0, client = 0 })' "$log_file" ||
  fail "workspace repress restores tiled when already full width"
pass "workspace repress restores tiled when already full width"

>"$log_file"
HYPR_ACTIVE_WORKSPACE=2 HYPR_FULLSCREEN=0 HYPR_ADDRESS=0x0 run_focus 2
! grep -Fq 'fullscreen_state' "$log_file" ||
  fail "workspace repress no-ops without a focused window"
! grep -Fq 'workspace = "2"' "$log_file" ||
  fail "workspace repress does not re-focus when already there with no window"
pass "workspace repress no-ops without a focused window"

touch "$home_dir/.local/state/omarchy/toggles/workspace-fullwidth-repress-off"
>"$log_file"
HYPR_ACTIVE_WORKSPACE=2 HYPR_FULLSCREEN=0 run_focus 2
grep -Fq 'hl.dsp.focus({ workspace = "2" })' "$log_file" ||
  fail "disabled repress always focuses the workspace"
! grep -Fq 'fullscreen_state' "$log_file" ||
  fail "disabled repress does not toggle full width"
pass "disabled repress always focuses the workspace"

if HOME="$home_dir" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-workspace-focus" 11 2>/dev/null; then
  fail "workspace focus rejects workspaces outside 1-10"
fi
pass "workspace focus rejects workspaces outside 1-10"

rm -f "$home_dir/.local/state/omarchy/toggles/workspace-fullwidth-repress-off"
if HOME="$home_dir" PATH="$stub_dir:$PATH" HYPRCTL_LOG="$log_file" \
  HYPRCTL_BROKEN=1 \
  "$ROOT/bin/omarchy-hyprland-workspace-focus" 2 2>/dev/null; then
  fail "workspace focus exits nonzero without a workspace id"
fi
pass "workspace focus exits nonzero without a workspace id"

cat >"$stub_dir/omarchy-toggle" <<'EOF'
#!/bin/bash
flag="$HOME/.local/state/omarchy/toggles/$1"
action="${2:-toggle}"
printf '%s\n' "$*" >>"$TOGGLE_LOG"
mkdir -p "$(dirname "$flag")"
case "$action" in
  on) touch "$flag" ;;
  off) rm -f "$flag" ;;
  toggle|"")
    if [[ -f $flag ]]; then
      rm -f "$flag"
    else
      touch "$flag"
    fi
    ;;
esac
EOF
chmod +x "$stub_dir/omarchy-toggle"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod +x "$stub_dir/omarchy-notification-send"

toggle_log="$tmpdir/toggle.log"
notify_log="$tmpdir/notify.log"
>"$toggle_log"
>"$notify_log"
# Feature off writes the off-flag (omarchy-toggle <flag> on).
HOME="$home_dir" TOGGLE_LOG="$toggle_log" NOTIFY_LOG="$notify_log" PATH="$stub_dir:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-toggle-workspace-fullwidth-repress" off
grep -Fq 'workspace-fullwidth-repress-off on' "$toggle_log" ||
  fail "preference off sets the off-flag"
grep -Fq 'Workspace repress full width disabled' "$notify_log" ||
  fail "preference toggle announces when disabled"
pass "preference off sets the off-flag"

>"$toggle_log"
>"$notify_log"
# Feature on clears the off-flag.
HOME="$home_dir" TOGGLE_LOG="$toggle_log" NOTIFY_LOG="$notify_log" PATH="$stub_dir:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-toggle-workspace-fullwidth-repress" on
grep -Fq 'workspace-fullwidth-repress-off off' "$toggle_log" ||
  fail "preference on clears the off-flag"
grep -Fq 'Workspace repress full width enabled' "$notify_log" ||
  fail "preference toggle announces when enabled"
pass "preference on clears the off-flag"

grep -Fq 'omarchy-hyprland-workspace-focus' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "tiling bindings route Super+workspace through workspace focus"
pass "tiling bindings route Super+workspace through workspace focus"

grep -Fq 'omarchy-toggle-workspace-fullwidth-repress' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "toggle menu exposes workspace full width preference"
pass "toggle menu exposes workspace full width preference"
