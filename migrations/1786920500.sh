echo "Lock the lid and idle the Radeon on 15-inch 2016–2017 MacBook Pros"

# 15" discrete-GPU models only. 13" T1 and T2 are unchanged.
if ! omarchy-hw-apple-mbp15-dgpu; then
  exit 0
fi

# Default AC profile is performance. Seed balanced once so a reboot does
# not cook the chassis. Do not overwrite a profile the user already chose.
ac_state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles/ac"
if [[ ! -f $ac_state ]]; then
  omarchy-powerprofiles-set ac balanced >/dev/null 2>&1 || true
fi

# shellcheck source=../install/hardware/apple/mbp15-dgpu.sh
source "$OMARCHY_PATH/install/hardware/apple/mbp15-dgpu.sh"

if (( $(id -u) != 0 )) && [[ $(mbp15_logind_dest) == /etc/* ]]; then
  exec sudo --preserve-env=OMARCHY_PATH,OMARCHY_DMI_PRODUCT_NAME,OMARCHY_MBP15_LOGIND,OMARCHY_MBP15_SLEEP,OMARCHY_MBP15_UDEV_SRC,OMARCHY_MBP15_UDEV_DEST,OMARCHY_MBP15_SKIP_SYSTEMCTL \
    /bin/bash -euo pipefail "$OMARCHY_PATH/migrations/1786920500.sh"
fi

mbp15_apply
