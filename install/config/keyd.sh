KEYD_CONF="${OMARCHY_KEYD_CONF:-/etc/keyd/default.conf}"

echo "Configuring keyd to put Escape on Caps Lock"

# Never clobber a config the user already owns. Anyone who installed keyd
# themselves has their own remapping here, and overwriting it would change
# their keyboard out from under them.
[[ -e $KEYD_CONF ]] && return 0

mkdir -p "$(dirname "$KEYD_CONF")"

cat >"$KEYD_CONF" <<'EOF'
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
