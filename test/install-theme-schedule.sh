#!/bin/bash

# Install the theme-schedule scripts from this repo into the live omarchy
# installation at ~/.local/share/omarchy without modifying any v3.6.0 files.
#
# Idempotent. Symlinks the new scripts so edits in the repo take effect
# immediately. Copies the systemd units (so they're owned by the user
# config dir) and installs the theme-set hook.
#
# Usage:
#   bash test/install-theme-schedule.sh             # install
#   bash test/install-theme-schedule.sh --uninstall # remove

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_BIN="$HOME/.local/share/omarchy/bin"
USER_SYSTEMD="$HOME/.config/systemd/user"
USER_HOOK_DIR="$HOME/.config/omarchy/hooks/theme-set.d"

SCRIPTS=(
  omarchy-theme-schedule-suncalc
  omarchy-theme-schedule-location
  omarchy-theme-schedule-apply
  omarchy-theme-schedule-record-slot
  omarchy-theme-schedule-enable
  omarchy-theme-schedule-disable
  omarchy-theme-schedule-status
  omarchy-theme-schedule-sleepwatch
)

UNITS=(
  omarchy-theme-schedule.service
  omarchy-theme-schedule.timer
  omarchy-theme-schedule-tzwatch.path
  omarchy-theme-schedule-sleepwatch.service
)

uninstall() {
  echo ":: Removing theme-schedule scripts and units"
  systemctl --user disable --now omarchy-theme-schedule.timer 2>/dev/null || true
  systemctl --user disable --now omarchy-theme-schedule-tzwatch.path 2>/dev/null || true
  systemctl --user disable --now omarchy-theme-schedule-sleepwatch.service 2>/dev/null || true

  for s in "${SCRIPTS[@]}"; do
    if [[ -L "$LIVE_BIN/$s" ]]; then
      rm -v "$LIVE_BIN/$s"
    fi
  done

  for u in "${UNITS[@]}"; do
    [[ -f "$USER_SYSTEMD/$u" ]] && rm -v "$USER_SYSTEMD/$u"
  done

  rm -rfv "$USER_SYSTEMD/omarchy-theme-schedule.timer.d"
  # Hook is now installed/removed by enable/disable, not the installer.
  rm -fv "$USER_HOOK_DIR/record-schedule-slot"
  rm -fv "$HOME/.local/share/omarchy/config/omarchy/hooks/theme-set.d/record-schedule-slot"

  # Restore original omarchy-hook if we replaced it
  if [[ -L "$LIVE_BIN/omarchy-hook" && -f "$LIVE_BIN/omarchy-hook.orig" ]]; then
    rm -v "$LIVE_BIN/omarchy-hook"
    mv -v "$LIVE_BIN/omarchy-hook.orig" "$LIVE_BIN/omarchy-hook"
  fi

  systemctl --user daemon-reload || true
  echo ":: Uninstalled."
}

# omarchy-hook in v3.6.0 only runs the single-file hook and aborts on
# failure. v3.7+ supports .d/ directories and tolerates failing hooks.
# Replace with the repo version when the installed copy is the older form.
maybe_upgrade_hook_runner() {
  local installed="$LIVE_BIN/omarchy-hook"
  local repo_version="$REPO_DIR/bin/omarchy-hook"

  [[ -f "$installed" ]] || return 0
  [[ -L "$installed" ]] && return 0  # already a symlink (presumed up-to-date)

  if grep -q 'HOOK_DIR' "$installed" 2>/dev/null; then
    return 0  # already supports .d/
  fi

  echo ":: Upgrading omarchy-hook to support .d/ directories"
  mv -v "$installed" "$installed.orig"
  ln -sf "$repo_version" "$installed"
}

install() {
  echo ":: Installing theme-schedule scripts to $LIVE_BIN (symlinked from repo)"
  mkdir -p "$LIVE_BIN" "$USER_SYSTEMD" "$USER_HOOK_DIR"

  maybe_upgrade_hook_runner

  for s in "${SCRIPTS[@]}"; do
    src="$REPO_DIR/bin/$s"
    dst="$LIVE_BIN/$s"
    if [[ ! -f "$src" ]]; then
      echo "Missing source: $src" >&2
      exit 1
    fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      echo "Refusing to overwrite non-symlink: $dst" >&2
      exit 1
    fi
    ln -sf "$src" "$dst"
    echo "  $dst -> $src"
  done

  echo ":: Installing systemd units to $USER_SYSTEMD"
  for u in "${UNITS[@]}"; do
    src="$REPO_DIR/config/systemd/user/$u"
    dst="$USER_SYSTEMD/$u"
    cp -v "$src" "$dst"
  done
  systemctl --user daemon-reload

  # The theme-set hook itself is installed by `omarchy theme schedule
  # enable` (and removed by disable). Its source lives at
  # $OMARCHY_PATH/config/omarchy/hooks/theme-set.d/record-schedule-slot.
  # In a real omarchy update, that file is shipped under config/omarchy/
  # already. For local development against an older $OMARCHY_PATH, we
  # symlink the repo file into place so enable's cp can find it.
  echo ":: Symlinking hook source into \$OMARCHY_PATH for local enable to find"
  installed_hook_src_dir="$HOME/.local/share/omarchy/config/omarchy/hooks/theme-set.d"
  mkdir -p "$installed_hook_src_dir"
  ln -sfn "$REPO_DIR/config/omarchy/hooks/theme-set.d/record-schedule-slot" \
    "$installed_hook_src_dir/record-schedule-slot"

  echo
  echo ":: Installed. Next steps:"
  echo "     omarchy-theme-schedule-status"
  echo "     omarchy-theme-schedule-enable           # interactive"
  echo "     omarchy-theme-schedule-enable <other>   # explicit other-phase theme"
  echo "     omarchy-theme-schedule-disable"
  echo
  echo "  To uninstall: bash $0 --uninstall"
}

case "${1:-}" in
  --uninstall|-u) uninstall ;;
  *)              install ;;
esac
