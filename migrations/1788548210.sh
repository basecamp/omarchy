echo "Prevent automatic wired connections to the internal Apple T2 interface"

# Do not let grep exit early: with pipefail, a chatty lspci can get SIGPIPE.
if lspci -nn | grep '106b:180[12]' >/dev/null; then
  t2_ncm_conf=${OMARCHY_T2_NCM_CONF:-/etc/NetworkManager/conf.d/90-omarchy-t2-ncm.conf}
  if [[ ! -e $t2_ncm_conf ]]; then
    sudo install -Dm644 "$OMARCHY_PATH/default/networkmanager/t2-ncm.conf" "$t2_ncm_conf"
  elif ! cmp -s "$OMARCHY_PATH/default/networkmanager/t2-ncm.conf" "$t2_ncm_conf"; then
    echo "Preserving customized $t2_ncm_conf; review the T2 no-auto-default exclusion."
  fi
  # Avoid interrupting networking during an update. At reboot, NetworkManager
  # drops its temporary generated profile and loads this exclusion. Persistent
  # profiles are deliberately untouched, even if named 'Wired connection 1'.
  echo "T2 network exclusion applies on reboot; existing saved profiles are unchanged."
fi
