# Fix NVMe suspend issues on MacBook models. Resolve controllers through the
# NVMe class instead of assuming a PCI address: 0000:01:00.0 is the Radeon on
# MacBookPro13,3, so the old fixed path disabled D3cold on the GPU and left the
# actual NVMe controller unchanged.
product_file="${OMARCHY_MACBOOK_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
product_name=$(cat "$product_file" 2>/dev/null || true)

if [[ $product_name =~ ^MacBook(8,1|9,1|10,1)$|^MacBookPro1[34],[123]$ ]]; then
  root_disk="${OMARCHY_MACBOOK_ROOT_DISK:-}"
  if [[ -z $root_disk ]]; then
    root_source=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    root_source=${root_source%%\[*}
    root_disk=$(lsblk -rsno NAME,TYPE "$root_source" 2>/dev/null |
      awk '$2 == "disk" { print $1; exit }')
  fi

  nvme_sysfs="${OMARCHY_MACBOOK_NVME_SYSFS:-/sys/class/nvme}"
  helper_source="$OMARCHY_INSTALL/hardware/apple/macbook-nvme-suspend"
  helper_target="${OMARCHY_MACBOOK_NVME_HELPER:-/etc/omarchy/hardware/macbook-nvme-suspend}"
  unit_file="${OMARCHY_MACBOOK_NVME_UNIT:-/etc/systemd/system/omarchy-nvme-suspend-fix.service}"
  nvme_settings=("$nvme_sysfs"/nvme*/device/d3cold_allowed)

  if [[ $root_disk != nvme* ]]; then
    echo "Root disk $root_disk is not NVMe; skipping the MacBook NVMe suspend fix"

    if [[ -f $unit_file ]]; then
      sudo systemctl disable --now omarchy-nvme-suspend-fix.service
      sudo mv -f "$unit_file" "$unit_file.disabled-non-nvme-root"
      sudo systemctl daemon-reload
    fi
  elif [[ -f ${nvme_settings[0]} ]]; then
    echo "Detected $product_name with an NVMe controller; disabling D3cold"

    sudo install -D -m 0755 "$helper_source" "$helper_target"
    {
      echo '[Unit]'
      echo 'Description=Omarchy NVMe Suspend Fix for MacBook'
      echo
      echo '[Service]'
      echo 'Type=oneshot'
      echo "ExecStart=$helper_target"
      echo
      echo '[Install]'
      echo 'WantedBy=multi-user.target'
    } | sudo tee "$unit_file" >/dev/null

    sudo systemctl daemon-reload
    sudo systemctl enable --now omarchy-nvme-suspend-fix.service
  else
    echo "No NVMe controller exposes d3cold_allowed; suspend fix not needed"
  fi
fi
