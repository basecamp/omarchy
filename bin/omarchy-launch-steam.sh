#!/bin/sh

if omarchy-pkg-present steam; then # Only apply if steam is installed

  # Launch steam in gaming mode ( inspired by https://github.com/cephalization/omarchy-steam-gaming-mode)

  POSSIBLE_GPUS=$(lspci | grep VGA)
  ACTIVE_MONITOR_INFO=$(hyprctl monitors -j | jq '.[] | select(.focused==true)')

  filter_info() {
    echo $ACTIVE_MONITOR_INFO | grep $1 | grep -o '[0-9]\+' | head -1
  }

  WIDTH=filter_info width
  HEIGHT=filter_info height
  REFRESH_RATE=filter_info refreshRate
  GAMESCOPE_ARGS=(
    -f
    -b
    --mangoapp
    --steam
    --expose-wayland
    -W "$WIDTH"
    -H "$HEIGHT"
    -r "$REFRESH_RATE"
    )


  # Restore state on exit

  trap "omarchy-toggle-screensaver; omarchy-toggle-hypridle"

  # Disable screensaver

  STATE_FILE=~/.local/state/omarchy/toggles/screensaver-off
  if [[ ! -f $STATE_FILE ]]; then
    mkdir -p "$(dirname $STATE_FILE)"
    touch $STATE_FILE
    notify-send "󱄄   Screensaver disabled"
  fi

  # Disable hypridle
  if pgrep -x hypridle >/dev/null; then
    pkill -x hypridle
    notify-send "󱫖    Stop locking computer when idle"
  fi


  # Kill existing steam instances
  killall steam

  # Launch gamescope with steam
    if echo $POSSIBLE_GPUS | grep NVIDIA; then
      args+=(-F nis)
    elif echo $POSSIBLE_GPUS | grep AMD; then
      args+=(-F fsr)
    fi
    gamescope "${args[@]}" -- steam -tenfoot
else
  echo "please install steam first by running omarchy-install-steam"
fi

