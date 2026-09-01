echo "Rebuild the boot image for a verified direct plain root"

hooks_conf="${OMARCHY_MKINITCPIO_HOOKS_CONF:-/etc/mkinitcpio.conf.d/omarchy_hooks.conf}"
rebuild_marker="${OMARCHY_PLAIN_ROOT_REBUILD_MARKER:-/var/lib/omarchy/migrations/1788279117}"

[[ -f $hooks_conf ]] || exit 0
[[ ! -e $rebuild_marker ]] || exit 0

resolved=$(bash -uc '
  FILES=()
  MODULES=()
  XKBLAYOUT=us
  source "$1"
  printf "OMARCHY_HOOKS:%s\n" "${HOOKS[*]}"
' -- "$hooks_conf") || exit 0

hooks=${resolved##*$'\n'}
[[ $hooks == OMARCHY_HOOKS:* ]] || exit 0
hooks=${hooks#OMARCHY_HOOKS:}
[[ " $hooks " != *" encrypt "* ]] || exit 0

echo "This machine has a direct plain root; rebuilding the boot image without the encrypt hook"
if omarchy-cmd-present limine-mkinitcpio; then
  sudo limine-mkinitcpio
else
  sudo mkinitcpio -P
fi
sudo install -Dm644 /dev/null "$rebuild_marker"
