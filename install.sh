#!/bin/bash
set -eE

OMARCHY_INSTALL=~/.local/share/omarchy/install
JOURNAL_TAG="omarchy-install"

INSTALL_START_TIME=$(date +%s)
echo "Omarchy installation started at $(date)" | systemd-cat -t "$JOURNAL_TAG" -p info

catch_preflight_errors() {
  echo -e "\n\e[31mOmarchy preflight failed!\e[0m"
  echo "Check the logs with: journalctl -t $JOURNAL_TAG -n 20"
  journalctl -t "$JOURNAL_TAG" -n 20 --no-pager
  exit 1
}
trap catch_preflight_errors ERR

echo "Loading installer experience..."

# Find and execute all .sh files in the preflight directory
if [[ -d "$OMARCHY_INSTALL/preflight" ]]; then
  while IFS= read -r script; do
    script_name=$(basename "$script")
    start_time=$(date +%s)
    echo "Starting: Preflight: $script_name" | systemd-cat -t "$JOURNAL_TAG" -p info
    bash "$script" 2>&1 | systemd-cat -t "$JOURNAL_TAG" -p info
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "Completed: Preflight: $script_name (${duration}s)" | systemd-cat -t "$JOURNAL_TAG" -p info
  done < <(find "$OMARCHY_INSTALL/preflight" -name "*.sh" -type f | sort)
fi

# Adjust font size based on detected resolution
FONT_SIZE=12 # Default
if [[ -r /sys/class/graphics/fb0/virtual_size ]]; then
  IFS=',' read -r WIDTH HEIGHT </sys/class/graphics/fb0/virtual_size
  if [[ $HEIGHT -ge 1440 ]]; then
    FONT_SIZE=14
  elif [[ $HEIGHT -ge 2160 ]]; then
    FONT_SIZE=18
  fi
fi

# Pass TEST_MODE if set (can be set when calling this script: TEST_MODE=true ./install-cage.sh)
TEST_MODE="${TEST_MODE:-false}"

MAIN_INSTALLER="${OMARCHY_INSTALL%/install}/install-main.sh"

OMARCHY_USER_NAME="$OMARCHY_USER_NAME" OMARCHY_USER_EMAIL="$OMARCHY_USER_EMAIL" TEST_MODE="$TEST_MODE" \
  cage -- alacritty \
  --config-file ~/.local/share/omarchy/themes/tokyo-night/alacritty.toml \
  -o font.size=$FONT_SIZE \
  -o 'font.normal.family="CaskaydiaMono Nerd Font"' \
  -e bash "$MAIN_INSTALLER" 2>&1 | systemd-cat -t "$JOURNAL_TAG" -p info

INSTALL_END_TIME=$(date +%s)
TOTAL_DURATION=$((INSTALL_END_TIME - INSTALL_START_TIME))
echo "Omarchy installation completed at $(date) - Total time: ${TOTAL_DURATION}s" | systemd-cat -t "$JOURNAL_TAG" -p info
