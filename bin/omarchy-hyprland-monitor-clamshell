#!/bin/bash

# omarchy:summary=Apply clamshell display state to Hyprland monitors
# omarchy:hidden=true

TOGGLES_DIR="$HOME/.local/state/omarchy/toggles/hypr"
CLAMSHELL_FLAG="$TOGGLES_DIR/internal-monitor-clamshell.lua"
MANUAL_DISABLE_FLAG="$TOGGLES_DIR/internal-monitor-disable.lua"
SCALE_STATE="$TOGGLES_DIR/internal-monitor-scale"
MONITOR_LUA="$HOME/.config/hypr/monitors.lua"

INTERNAL=$(omarchy-hyprland-monitor-laptop)

# INTERNAL is written into generated Lua and hyprctl eval/dispatch below, so a
# name that is not a plain connector string could execute on the next reload.
# Names come from hyprctl; a user-created headless output can carry anything.
if [[ -n $INTERNAL && ! $INTERNAL =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Refusing unsafe internal monitor name" >&2
  exit 1
fi

valid_scale() {
  [[ $1 =~ ^[0-9]+([.][0-9]+)?$ ]]
}

scales_match() {
  local left="$1"
  local right="$2"

  valid_scale "$left" && valid_scale "$right" || return 1
  awk -v left="$left" -v right="$right" 'BEGIN {
    diff = left - right
    if (diff < 0) diff = -diff
    exit(diff < 0.001 ? 0 : 1)
  }'
}

lua_identifier() {
  [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# Value assigned by `local <name> = ...`, without its quotes or trailing comment.
# Only a lone scalar counts: an expression like `1080 / 720` must stay unresolved
# so the caller falls back rather than applying the first half of the sum.
lua_local_value() {
  local name="$1" value
  lua_identifier "$name" && [[ -f $MONITOR_LUA ]] || return 0

  value=$(sed -nE 's/^[[:space:]]*local[[:space:]]+'"$name"'[[:space:]]*=[[:space:]]*("[^"]*"|[^"[:space:]]+)[[:space:]]*(--.*)?$/\1/p' "$MONITOR_LUA" | head -1)
  [[ $value == \"*\" ]] && value="${value:1:-1}"
  printf '%s\n' "$value"
}

# A quoted capture is a Lua string and stands for itself; a bare word may instead
# name a local the rule refers to, as the shipped scale = omarchy_monitor_scale
# does. A bare word naming no local is left alone to fail validation.
lua_scalar() {
  local value="$1" resolved

  if [[ $value == \"*\" ]]; then
    printf '%s\n' "${value:1:-1}"
    return
  fi

  resolved=$(lua_local_value "$value")
  printf '%s\n' "${resolved:-$value}"
}

# The config with its comments cut away, so commented-out text can pose neither
# as a rule nor as one of its keys.
monitor_rules() {
  [[ -f $MONITOR_LUA ]] || return 0

  sed -E -e 's/--\[\[[^]]*\]\]//g' -e 's/--.*$//' "$MONITOR_LUA"
}

monitor_rule_regex() {
  printf '^[[:space:]]*hl\\.monitor\\(\\{.*output[[:space:]]*=[[:space:]]*"%s"' "$1"
}

# A key is preceded by a table separator, so a longer key cannot stand in for it,
# and its value is the whole of what sits between the `=` and the next separator.
# Anything else is an expression this cannot evaluate.
configured_monitor_value() {
  local output="$1" key="$2" value

  value=$(monitor_rules | sed -nE '/'"$(monitor_rule_regex "$output")"'/s/.*[{,;[:space:]]'"$key"'[[:space:]]*=[[:space:]]*("[^"]*"|[^,;}[:space:]]+)[[:space:]]*([,;}].*)?$/\1/p' | head -1)
  lua_scalar "$value"
}

configured_internal_monitor_value() {
  [[ -n $INTERNAL ]] || return 0

  configured_monitor_value "$INTERNAL" "$1"
}

configured_monitor_scale() {
  local scale
  scale=$(configured_internal_monitor_value scale)
  # An internal rule that names a scale settles it, even when the name resolves
  # to nothing usable. Only a rule that names none at all defers to the catch-all,
  # which is the scale Omarchy has always applied for that config.
  [[ -n $scale ]] || scale=$(configured_monitor_value "" scale)
  # No rule carries a scale at all: fall back to Omarchy's own knob.
  [[ -n $scale ]] || scale=$(lua_local_value omarchy_monitor_scale)

  printf '%s\n' "$scale"
}

current_internal_scale() {
  [[ -n $INTERNAL ]] || return 0
  hyprctl monitors all -j | jq -r --arg internal "$INTERNAL" '.[] | select(.name == $internal and .disabled != true) | .scale' | head -1
}

store_internal_scale() {
  local scale="$1"
  valid_scale "$scale" || return 0

  mkdir -p "$TOGGLES_DIR"
  printf '%s\n' "$scale" >"$SCALE_STATE"
}

remember_internal_scale() {
  local scale
  scale=$(current_internal_scale)
  store_internal_scale "$scale"
}

# $1 is the configured scale when the caller has already read it, so one sync
# does not parse the config twice.
read_monitor_scale() {
  local scale

  if (( $# )); then
    scale="$1"
  else
    scale=$(configured_monitor_scale)
  fi

  if valid_scale "$scale"; then
    echo "$scale"
    return
  fi

  if [[ -f $SCALE_STATE ]]; then
    scale=$(<"$SCALE_STATE")
    if valid_scale "$scale"; then
      echo "$scale"
      return
    fi
  fi

  echo 2
}

read_monitor_position() {
  local position
  position=$(configured_internal_monitor_value position)
  if [[ $position =~ ^[-[:alnum:]_.+]+$ ]]; then
    echo "$position"
    return
  fi

  echo auto
}

enable_internal_output() {
  [[ -n $INTERNAL ]] || return 0
  local scale="${1:-}"
  local position
  [[ -n $scale ]] || scale=$(read_monitor_scale)
  position=$(read_monitor_position)
  hyprctl eval "hl.monitor({ output = \"$INTERNAL\", mode = \"preferred\", position = \"$position\", scale = $scale })" >/dev/null 2>&1 || true
}

sync_internal_scale() {
  [[ -n $INTERNAL ]] || return 0
  local configured_scale
  local desired_scale
  local active_scale

  configured_scale=$(configured_monitor_scale)
  active_scale=$(current_internal_scale)

  # A config without a usable number -- the default "auto", or an expression
  # only Hyprland's Lua can evaluate -- delegates the scale to the compositor,
  # so whatever it resolved for the enabled panel IS the configured scale.
  # There is no number to correct it toward: substituting one makes the scale
  # flap between that number and the compositor's own value on every idle-wake.
  # Only a panel that is off altogether still gets a hand below, from the
  # remembered scale.
  if ! valid_scale "$configured_scale" && valid_scale "$active_scale"; then
    return 0
  fi

  desired_scale=$(read_monitor_scale "$configured_scale")
  scales_match "$active_scale" "$desired_scale" && return 0

  enable_internal_output "$desired_scale"
}

dpms_internal() {
  local action="$1"

  [[ -n $INTERNAL ]] || return 0
  hyprctl dispatch "hl.dsp.dpms({ action = \"$action\", monitor = \"$INTERNAL\" })" >/dev/null 2>&1 || true
}

enable_internal() {
  local changed=0

  if [[ -f $CLAMSHELL_FLAG ]]; then
    rm -f "$CLAMSHELL_FLAG"
    changed=1
  fi

  if (( changed )); then
    hyprctl reload >/dev/null 2>&1 || true
  fi

  [[ -f $MANUAL_DISABLE_FLAG ]] && omarchy-hyprland-monitor-external-active && return 0
  sync_internal_scale

  if (( changed )); then
    dpms_internal enable
  fi
}

disable_internal() {
  [[ -n $INTERNAL ]] || exit 0
  [[ -f $MANUAL_DISABLE_FLAG ]] && return 0

  mkdir -p "$TOGGLES_DIR"
  remember_internal_scale

  local config
  config=$(printf 'hl.monitor({ output = "%s", disabled = true })' "$INTERNAL")

  if [[ ! -f $CLAMSHELL_FLAG ]] || [[ $(< "$CLAMSHELL_FLAG") != $config ]]; then
    printf '%s\n' "$config" >"$CLAMSHELL_FLAG"
    hyprctl reload >/dev/null 2>&1 || true
  fi
}

omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true
omarchy-hyprland-monitor-internal-mirror recover >/dev/null 2>&1 || true

if omarchy-hw-clamshell && omarchy-hyprland-monitor-external-active; then
  disable_internal
else
  enable_internal
fi
