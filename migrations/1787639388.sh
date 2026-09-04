echo "Point ~/.XCompose and the power udev rules at the packaged Omarchy tree"

# Omarchy 3 wrote ~/.XCompose with an include under ~/.local/share/omarchy and
# installed udev rules that ran omarchy-powerprofiles-set and
# omarchy-wifi-powersave out of that same checkout. The quattro upgrade rewrote
# neither, so both only kept working through the ~/.local/share/omarchy compat
# symlink it leaves behind. Remove that symlink -- an obvious cleanup next to the
# upgrade's backup of the old checkout -- and xkbcommon rejects the whole
# ~/.XCompose on the failed include, taking every CapsLock sequence (emoji,
# name, email) with it, while udev keeps shelling out to a path that no longer
# exists on every power-source change. Point the include at the packaged file
# and drop the rules: quattro's shell switches power profiles itself.

xcompose="$HOME/.XCompose"
rules_dir="${OMARCHY_UDEV_RULES_DIR:-/etc/udev/rules.d}"

if [[ -f $xcompose ]] && grep -q 'local/share/omarchy/default/xcompose' "$xcompose"; then
  sed -i -E 's|^([[:space:]]*include[[:space:]]+")[^"]*/\.local/share/omarchy/default/xcompose"|\1/usr/share/omarchy/default/xcompose"|' "$xcompose"
  # A headless update has no session to reload; the next login picks it up.
  omarchy-restart-xcompose >/dev/null 2>&1 || true
fi

reload_udev=0
for rule in 99-power-profile 99-wifi-powersave; do
  file="$rules_dir/$rule.rules"
  if [[ -f $file ]] && grep -q 'local/share/omarchy' "$file"; then
    sudo rm -f "$file"
    reload_udev=1
  fi
done

if (( reload_udev )); then
  sudo udevadm control --reload || true
fi
