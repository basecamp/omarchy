echo "Fix clipboard loop caused by wl-x11-sync"

SCRIPT="$HOME/.local/bin/wl-x11-sync.sh"
UNIT="$HOME/.config/systemd/user/wl-x11-sync.service"

# Some setups end up with a two-way clipboard<->primary sync using wl-paste/wl-copy.
# That can create a feedback loop (clipboard change -> set primary -> primary change
# -> set clipboard ...) and effectively break pasting.

if [[ -f "$SCRIPT" ]]; then
  if grep -qE 'wl-paste --type text --watch wl-copy( --primary)?' "$SCRIPT"; then
    BACKUP="$SCRIPT.bak.$(date +%s)"
    cp -a "$SCRIPT" "$BACKUP"

    cat >"$SCRIPT" <<'EOF'
#!/usr/bin/env sh

# Wayland PRIMARY -> CLIPBOARD (Wayland + X11)
#
# Keep this one-way. Two-way sync can create an infinite feedback loop and
# break copy/paste.

wl-paste --primary --type text --watch sh -c 'cat | tee >(wl-copy) | xclip -selection clipboard -i -f >/dev/null'
EOF

    chmod +x "$SCRIPT"
  fi
fi

if [[ -f "$UNIT" ]]; then
  systemctl --user daemon-reload || true
  systemctl --user restart wl-x11-sync.service || true
fi
