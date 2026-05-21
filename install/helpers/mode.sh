# OMARCHY_INSTALL_MODE is one of: iso-chroot, online-package, online-git
# Back-compat shims honor the older OMARCHY_CHROOT_INSTALL and
# OMARCHY_ONLINE_INSTALL flags during transition.

detect_install_mode() {
  if [[ -n ${OMARCHY_INSTALL_MODE:-} ]]; then
    return
  fi

  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    export OMARCHY_INSTALL_MODE=iso-chroot
  elif [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
    export OMARCHY_INSTALL_MODE=online-git
  elif [[ ${OMARCHY_PATH:-} == /usr/share/omarchy ]]; then
    export OMARCHY_INSTALL_MODE=online-package
  else
    export OMARCHY_INSTALL_MODE=online-git
  fi
}

install_mode_is() {
  [[ ${OMARCHY_INSTALL_MODE:-} == "$1" ]]
}

# Sets OMARCHY_CHROOT_INSTALL=1 and OMARCHY_ONLINE_INSTALL=true so callers
# that still check the legacy vars keep working through the transition.
export_legacy_mode_flags() {
  case ${OMARCHY_INSTALL_MODE:-} in
    iso-chroot)
      export OMARCHY_CHROOT_INSTALL=1
      ;;
    online-git)
      export OMARCHY_ONLINE_INSTALL=true
      ;;
  esac
}

export -f install_mode_is
