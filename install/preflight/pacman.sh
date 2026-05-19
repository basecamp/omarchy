if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  omarchy-pkg-add base-devel

  if ! declare -F use_omarchy_pacman_config >/dev/null; then
    source "${OMARCHY_INSTALL:-${BASH_SOURCE[0]%/*}/..}/helpers/pacman.sh"
  fi

  # Configure pacman
  use_omarchy_pacman_config

  sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

  sudo pacman -Sy
  omarchy-pkg-add omarchy-keyring

  # Refresh all repos
  sudo pacman -Syyuu --noconfirm
fi
