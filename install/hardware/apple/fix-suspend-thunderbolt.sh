# Fix Thunderbolt/xHCI sleep stall on MacBook Pro models (2016-2017)
# In ACPI S3 sleep, Apple firmware cuts power to the Alpine Ridge controller (8086:15d2/15d4).
# Removing the unpowered xHCI controller before sleep prevents xhci_hcd from freezing for ~130s on wake.
macbook_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ $macbook_model =~ MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook Pro with Alpine Ridge Thunderbolt ($macbook_model)"
  echo "Applying Thunderbolt and display sleep fixes..."

  sudo mkdir -p /etc/systemd/system-sleep
  sudo tee /etc/systemd/system-sleep/omarchy-macbook-sleep.sh >/dev/null <<'EOF'
#!/bin/bash
case "$1/$2" in
  pre/*)
    for dev in /sys/bus/pci/devices/*; do
      if [[ -f "$dev/vendor" && -f "$dev/device" ]]; then
        if [[ $(cat "$dev/vendor" 2>/dev/null) == "0x8086" && $(cat "$dev/device" 2>/dev/null) == "0x15d4" ]]; then
          echo 1 > "$dev/remove" 2>/dev/null || true
        fi
      fi
    done
    [[ -d /sys/bus/pci/devices/0000:07:00.0 ]] && echo 1 > /sys/bus/pci/devices/0000:07:00.0/remove 2>/dev/null || true

    [[ -d /sys/module/thunderbolt ]] && modprobe -r thunderbolt 2>/dev/null || true
    [[ -d /sys/module/facetimehd ]] && modprobe -r facetimehd 2>/dev/null || true
    ;;

  post/*)
    for user_dir in /run/user/*; do
      if [[ -d "$user_dir/hypr" ]]; then
        uid=$(basename "$user_dir")
        uname=$(id -nu "$uid" 2>/dev/null)
        sig=$(ls -td "$user_dir/hypr/"* 2>/dev/null | head -1 | xargs basename 2>/dev/null)
        if [[ -n "$uname" && -n "$sig" ]]; then
          ( runuser -u "$uname" -- env XDG_RUNTIME_DIR="$user_dir" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true ) &
        fi
      fi
    done

    [[ -d /sys/bus/pci/devices/0000:00:1c.4 ]] && ( sleep 2 && echo 1 > /sys/bus/pci/devices/0000:00:1c.4/rescan ) >/dev/null 2>&1 &
    ;;
esac
EOF

  sudo chmod 755 /etc/systemd/system-sleep/omarchy-macbook-sleep.sh

  sudo mkdir -p /etc/modprobe.d
  echo "blacklist thunderbolt" | sudo tee /etc/modprobe.d/disable-thunderbolt.conf >/dev/null
fi
