#!/bin/bash

# Seed the Korean input method for machines installed with the Korean keyboard
# choice. There is no Korean console keymap, so the picker persists that choice
# as XKBLAYOUT=kr in /etc/vconsole.conf (the console itself stays on us); this
# is the marker read here. fcitx5 already runs in every session for the
# XCompose sequences, so Korean only needs the hangul engine in this user's
# input methods and a toggle key.
#
# The 한/영 key on Korean keyboards emits the Hangul keysym on every XKB
# layout (xkb maps <HNGL> globally), so binding Hangul as the trigger makes
# that key the Korean/English toggle without touching Caps Lock, which stays
# the compose key. Control+space remains as a fallback for keyboards without a
# dedicated 한/영 key.
#
# fcitx5 owns these two files: it writes a default profile the moment it starts,
# and rewrites both when it saves. Hyprland's autostart runs first-run well
# after graphical-session.target has started fcitx5, so the files always exist
# by the time this runs and their mere presence proves nothing -- the guards
# below test for the hangul engine instead. fcitx5 is stopped for the write
# because its own save-on-exit would otherwise put the default group straight
# back over what was just written.
#
# A no-op on non-Korean machines, and on any account that already lists hangul,
# so a user's own fcitx5 setup survives a forced first-run rerun.

set -euo pipefail

xkb_layout=$(sed -n 's/^XKBLAYOUT=//p' /etc/vconsole.conf 2>/dev/null | tail -n 1)
xkb_layout=${xkb_layout//[\"\']/}
if [[ ${xkb_layout%%,*} != "kr" ]]; then
  exit 0
fi

profile=~/.config/fcitx5/profile
config=~/.config/fcitx5/config

needs_profile() { ! grep -qx 'Name=hangul' "$profile" 2>/dev/null; }
needs_config() { ! grep -qx '0=Hangul' "$config" 2>/dev/null; }

if ! needs_profile && ! needs_config; then
  exit 0
fi

mkdir -p ~/.config/fcitx5
systemctl --user stop omarchy-fcitx5.service 2>/dev/null || true

if needs_profile; then
  cat >"$profile" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=hangul

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=hangul
# Layout
Layout=

[GroupOrder]
0=Default
EOF
  # fcitx5 writes the profile private; match it rather than leaving the group
  # and world a copy of what this user types with.
  chmod 600 "$profile"
fi

if needs_config; then
  # fcitx5 writes list-valued options as their own section
  # ([Hotkey/TriggerKeys] with 0=, 1= beneath it). A bare "TriggerKeys=" line
  # under [Hotkey] would silently set the list empty -- no toggle key at all.
  cat >"$config" <<'EOF'
[Hotkey/TriggerKeys]
# Hangul is what the 한/영 key on Korean keyboards emits.
0=Hangul
1=Control+space

[Behavior]
# Start in English; the trigger switches to Korean.
ActiveByDefault=False
EOF
fi

# Only bring it back up when there is a session to come back to; an update over
# SSH has a user manager and no display, and the unit's own
# ConditionEnvironment keeps it stopped there.
systemctl --user start omarchy-fcitx5.service 2>/dev/null || true
