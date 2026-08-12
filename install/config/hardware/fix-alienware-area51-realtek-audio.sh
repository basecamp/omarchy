# Work around SOF/SoundWire init race and RT1320 UCM mismatch on
# Alienware Area-51 AA18250 systems.

system_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"

if echo "$system_vendor" | grep -qi "^alienware$" && echo "$product_name" | grep -Eqi "^(alienware 18 area-51|aa18250)$"; then
  echo "Detected $system_vendor $product_name. Applying SOF/RT1320 audio workaround."

  sudo cp "$OMARCHY_PATH/default/systemd/system/fix-sof-audio.service" /etc/systemd/system/fix-sof-audio.service
  sudo systemctl daemon-reload
  chrootable_systemctl_enable fix-sof-audio.service

  # Write UCM override to /etc/alsa/ucm2/ so it survives alsa-ucm-conf upgrades.
  source_ucm="/usr/share/alsa/ucm2/sof-soundwire/rt1320.conf"
  override_ucm="/etc/alsa/ucm2/sof-soundwire/rt1320.conf"
  if [[ -f "$source_ucm" ]]; then
    sudo mkdir -p "$(dirname "$override_ucm")"
    if [[ ! -f "$override_ucm" ]]; then
      sudo cp "$source_ucm" "$override_ucm"
    fi

    # Remove nonexistent rt1320-2 control reference.
    sudo sed -i '/Macro\.num3\.rt1320spk/d' "$override_ucm"

    # Fix stereo routing for second amp: L,L -> L,R.
    sudo sed -i '/Macro\.num2\.rt1320spk[[:space:]]*{/,/}/{s/Sel "L,L"/Sel "L,R"/;}' "$override_ucm"
    if sudo grep -qE 'Sel "L,L"' "$override_ucm"; then
      echo "Warning: RT1320 UCM stereo patch may not have applied cleanly — verify $override_ucm" >&2
    fi
  fi
fi
