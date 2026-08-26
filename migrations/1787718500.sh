echo "Install Intel BE200/BE211 sleep reset hook"

if lspci -nn 2>/dev/null | grep -qE '\[8086:(e440|272b)\]'; then
  hook_src="$OMARCHY_PATH/default/systemd/system-sleep/iwlwifi-reset"
  hook_dest="/usr/lib/systemd/system-sleep/iwlwifi-reset"

  if [[ -f $hook_src ]]; then
    if [[ ! -f $hook_dest ]] || ! cmp -s "$hook_src" "$hook_dest"; then
      sudo mkdir -p /usr/lib/systemd/system-sleep 2>/dev/null || true
      sudo cp -p "$hook_src" "$hook_dest" 2>/dev/null || echo "Could not install $hook_dest (requires sudo privileges)" >&2
    fi
  fi
fi
