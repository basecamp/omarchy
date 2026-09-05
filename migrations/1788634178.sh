echo "Keep BCM43602 out of PCI D3 on 15-inch 2016–2017 MacBook Pros"

# 15" discrete-GPU models only. Existing installs already ran the lid/Radeon
# migration and still put the Broadcom card to sleep on lid close.
if ! omarchy-hw-apple-mbp15-dgpu; then
  exit 0
fi

# shellcheck source=../install/hardware/apple/mbp15-dgpu.sh
source "$OMARCHY_PATH/install/hardware/apple/mbp15-dgpu.sh"

if (( $(id -u) != 0 )) && [[ $(mbp15_wifi_udev_dest) == /etc/* ]]; then
  exec sudo --preserve-env=OMARCHY_PATH,OMARCHY_DMI_PRODUCT_NAME,OMARCHY_MBP15_LOGIND,OMARCHY_MBP15_SLEEP,OMARCHY_MBP15_UDEV_SRC,OMARCHY_MBP15_UDEV_DEST,OMARCHY_MBP15_WIFI_UDEV_SRC,OMARCHY_MBP15_WIFI_UDEV_DEST,OMARCHY_MBP15_SKIP_SYSTEMCTL \
    /bin/bash -euo pipefail "$OMARCHY_PATH/migrations/1788634178.sh"
fi

mbp15_apply
