# OMARCHY_INSTALL_MODE is one of: online, offline
#   online  - bootstrap installed omarchy-* packages from the omacom-pkgs.org
#             repo on an existing Arch system, then ran install.sh.
#   offline - ISO build: archinstall pacstrapped the bundled mirror; install.sh
#             runs in the chroot before the user's first boot.
# Legacy OMARCHY_CHROOT_INSTALL and OMARCHY_ONLINE_INSTALL still work as
# shims during transition.

detect_install_mode() {
  if [[ -n ${OMARCHY_INSTALL_MODE:-} ]]; then
    case $OMARCHY_INSTALL_MODE in
      online|offline) ;;
      *)
        echo "Error: invalid OMARCHY_INSTALL_MODE=$OMARCHY_INSTALL_MODE" >&2
        echo "       must be one of: online, offline" >&2
        exit 1
        ;;
    esac
    export OMARCHY_INSTALL_MODE
    return
  fi

  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    export OMARCHY_INSTALL_MODE=offline
  elif [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
    export OMARCHY_INSTALL_MODE=online
  else
    export OMARCHY_INSTALL_MODE=online
  fi
}

install_mode_is() {
  [[ ${OMARCHY_INSTALL_MODE:-} == "$1" ]]
}

# Synchronize the legacy vars to the canonical mode so callers that still
# check OMARCHY_CHROOT_INSTALL / OMARCHY_ONLINE_INSTALL agree with us.
export_legacy_mode_flags() {
  case ${OMARCHY_INSTALL_MODE:-} in
    offline)
      export OMARCHY_CHROOT_INSTALL=1
      unset OMARCHY_ONLINE_INSTALL
      ;;
    online)
      export OMARCHY_ONLINE_INSTALL=true
      unset OMARCHY_CHROOT_INSTALL
      ;;
  esac
}

export -f install_mode_is
