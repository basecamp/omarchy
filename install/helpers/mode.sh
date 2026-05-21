# OMARCHY_INSTALL_MODE is one of: iso-chroot, online-package, online-git
# Back-compat shims honor the older OMARCHY_CHROOT_INSTALL and
# OMARCHY_ONLINE_INSTALL flags during transition.

detect_install_mode() {
  if [[ -n ${OMARCHY_INSTALL_MODE:-} ]]; then
    case $OMARCHY_INSTALL_MODE in
      iso-chroot|online-package|online-git) ;;
      *)
        echo "Error: invalid OMARCHY_INSTALL_MODE=$OMARCHY_INSTALL_MODE" >&2
        echo "       must be one of: iso-chroot, online-package, online-git" >&2
        exit 1
        ;;
    esac
    export OMARCHY_INSTALL_MODE
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

# Synchronize the legacy vars to the canonical mode so callers that still
# check OMARCHY_CHROOT_INSTALL / OMARCHY_ONLINE_INSTALL agree with us
# (including unsetting contradictory ones).
export_legacy_mode_flags() {
  case ${OMARCHY_INSTALL_MODE:-} in
    iso-chroot)
      export OMARCHY_CHROOT_INSTALL=1
      unset OMARCHY_ONLINE_INSTALL
      ;;
    online-git)
      export OMARCHY_ONLINE_INSTALL=true
      unset OMARCHY_CHROOT_INSTALL
      ;;
    online-package)
      unset OMARCHY_CHROOT_INSTALL
      unset OMARCHY_ONLINE_INSTALL
      ;;
  esac
}

export -f install_mode_is
