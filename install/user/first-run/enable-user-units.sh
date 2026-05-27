#!/bin/bash

# Enable the user systemd units we ship. Runs at first-run rather than at
# finalize-user time because the user manager isn't live during the ISO
# chroot — by first-run, the Hyprland/uwsm session is up and `systemctl
# --user enable` writes the correct .wants symlinks based on each unit's
# [Install]/WantedBy. ConditionPath* in the unit files keep the enabled
# units inert on hardware they don't apply to.

set -euo pipefail

systemctl --user enable \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service
