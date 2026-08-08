echo "Install keyd and put Escape on Caps Lock"

KEYD_CONF="${OMARCHY_KEYD_CONF:-/etc/keyd/default.conf}"

omarchy-pkg-add keyd

# Never clobber a config the user already owns. Anyone who installed keyd
# themselves has their own remapping here.
if [[ ! -e $KEYD_CONF ]]; then
  sudo mkdir -p "$(dirname "$KEYD_CONF")"
  sudo tee "$KEYD_CONF" >/dev/null <<'EOF'
# Caps Lock becomes Escape (tap) and a navigation layer (hold).
#
#   Caps Lock tap        Escape
#   Caps Lock + hjkl     arrow keys
#   Caps Lock + u / d    page up / page down
#   Caps Lock + a / e    home / end
#   Caps Lock + b        backspace
#   Caps Lock + c        Compose
#   Caps Lock + q        Caps Lock
#   both Shifts          Caps Lock (shift:both_capslock_cancel; a lone Shift
#                        afterwards releases it)
#
# This works with Hyprland's keymap, which sets compose:menu. keyd only
# rewrites keycodes; xkb decides what they mean. Override kb_options without
# compose:menu and the Compose binding below stops composing.

[ids]
*

[main]
# Tap for Escape, hold for the Omarchy layer below.
capslock = overload(omarchy, esc)

# Emit the raw Shift keycodes rather than letting them activate keyd's
# predefined `shift` layer. Without this xkb never sees Left and Right Shift as
# two distinct keys held together, which is what shift:both_capslock_cancel
# needs to set Caps Lock.
leftshift = leftshift
rightshift = rightshift

[omarchy]
# Navigation without leaving the home row.
h = left
j = down
k = up
l = right
u = pageup
d = pagedown
a = home
e = end
b = backspace

# Synthesize keycodes back to xkb rather than handling these in keyd, so the
# Hyprland keymap stays the single source of truth for what they mean:
#   c -> KEY_COMPOSE  -> <MENU> -> Multi_key (via compose:menu)
#   q -> KEY_CAPSLOCK -> <CAPS> -> Caps_Lock
c = compose
q = capslock
EOF
fi

sudo systemctl enable --now keyd.service

# Compose moved from <CAPS> to <MENU>, which only works for people running the
# stock kb_options. Anyone who set their own keeps compose:caps, and keyd now
# holds Caps Lock, so their Compose key would silently stop working.
if [[ -f ~/.config/hypr/input.lua ]] &&
  grep -qE '^[^-]*kb_options.*compose:caps' ~/.config/hypr/input.lua; then
  echo
  echo "  Your ~/.config/hypr/input.lua sets kb_options with compose:caps."
  echo "  keyd now holds Caps Lock, so Compose there will no longer fire."

  # An existing /etc/keyd/default.conf is left alone above, and it need not
  # bind Compose at all, so only point at Caps Lock + c when it really does.
  if grep -qE '^[[:space:]]*c[[:space:]]*=[[:space:]]*compose[[:space:]]*$' "$KEYD_CONF"; then
    echo "  Change it to compose:menu to reach Compose with Caps Lock + c."
  else
    echo "  Your own /etc/keyd/default.conf was kept as it was. Point some key"
    echo "  there at a Compose keycode and set kb_options to match it:"
    echo "    compose (KEY_COMPOSE) needs compose:menu"
    echo "    capslock (KEY_CAPSLOCK) needs compose:caps"
  fi
  echo
fi
