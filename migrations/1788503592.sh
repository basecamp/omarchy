echo "Repair the MacBook NVMe suspend service device targeting"

# The old unit hard-coded 0000:01:00.0. On dual-GPU MacBooks that is the AMD
# display controller, not NVMe. Re-run the hardware leaf so the service follows
# the NVMe class when root is on NVMe, or disables itself for external roots.
unit_file="${OMARCHY_MACBOOK_NVME_UNIT:-/etc/systemd/system/omarchy-nvme-suspend-fix.service}"
if [[ -f $unit_file ]] && grep -Fq '0000\:01\:00.0/d3cold_allowed' "$unit_file"; then
  : "${OMARCHY_PATH:=/usr/share/omarchy}"
  : "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
  # shellcheck source=../install/hardware/apple/fix-suspend-nvme.sh
  source "$OMARCHY_INSTALL/hardware/apple/fix-suspend-nvme.sh"
fi
