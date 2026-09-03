echo "Require signed packages from the Omarchy repository"

# The [omarchy] repo predates the Omarchy packaging key, so existing installs
# carry a SigLevel override that also accepts unsigned packages. Packages are
# signed now, so drop the override and let the repo inherit the global
# SigLevel = Required DatabaseOptional like every other repo. Machine-wide and
# self-detecting, so another user's rerun no-ops.
omarchy_sig_override='SigLevel = Optional TrustAll'

if [[ -f /etc/pacman.conf ]] &&
  sed -n '/^\[omarchy\]/,/^\[/p' /etc/pacman.conf | grep -qxF "$omarchy_sig_override"; then
  # Requiring signatures with an untrusted packaging key would fail every
  # omarchy transaction, including the one that could repair it.
  if omarchy-pkg-missing omarchy-keyring ||
    ! sudo pacman-key --list-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 &>/dev/null; then
    omarchy-update-keyring
  fi

  sudo sed -i "/^\[omarchy\]/,/^\[/{/^$omarchy_sig_override$/d}" /etc/pacman.conf
fi
