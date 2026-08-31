echo "Point XCompose at a home-local table so sandboxed apps keep compose"

# ~/.XCompose with an absolute include into /usr/share/omarchy parses on the
# host, but Steam's pressure-vessel (and other sandboxes that bind $HOME without
# the host /usr) cannot open that path. xkbcommon then rejects the whole file,
# so every compose sequence dies inside the container. Omarchy 3 used a
# %H-relative include; restore that shape with a real home-local copy of the
# packaged table rather than a checkout symlink under ~/.local/share/omarchy.

packaged_xcompose="${OMARCHY_PATH}/default/xcompose"
home_xcompose="$HOME/.XCompose.omarchy"
xcompose="$HOME/.XCompose"

[[ -f $packaged_xcompose ]] || exit 0

cp "$packaged_xcompose" "$home_xcompose"
chmod 644 "$home_xcompose"

[[ -f $xcompose ]] || exit 0

# Absolute packaged path (fresh Omarchy 4 / upgrade-to-quattro seed) and the
# Omarchy 3 %H/.local/share/... form both become the home-local include.
if grep -Eq '^[[:space:]]*include[[:space:]]+"(/usr/share/omarchy/default/xcompose|%H/\.local/share/omarchy/default/xcompose|[^"]*/\.local/share/omarchy/default/xcompose)"[[:space:]]*$' "$xcompose"; then
  # Three separate replacements keep the sed program free of nested | groups
  # that trip portable ERE parsing.
  sed -i -E \
    -e 's|^([[:space:]]*include[[:space:]]+")/usr/share/omarchy/default/xcompose("[[:space:]]*)$|\1%H/.XCompose.omarchy\2|' \
    -e 's|^([[:space:]]*include[[:space:]]+")%H/\.local/share/omarchy/default/xcompose("[[:space:]]*)$|\1%H/.XCompose.omarchy\2|' \
    -e 's|^([[:space:]]*include[[:space:]]+")[^"]*/\.local/share/omarchy/default/xcompose("[[:space:]]*)$|\1%H/.XCompose.omarchy\2|' \
    "$xcompose"
  omarchy-restart-xcompose >/dev/null 2>&1 || true
fi
