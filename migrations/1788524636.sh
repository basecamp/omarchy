echo "Stabilize AMDGPU startup on iMac20,2 with Radeon Pro 5700 XT"

detector="$OMARCHY_PATH/bin/omarchy-hw-imac20-amdgpu-uclk"
marker="${OMARCHY_IMAC20_AMDGPU_MARKER:-/var/lib/omarchy/migrations/1788524636}"
system_path="${OMARCHY_IMAC20_AMDGPU_SYSTEM_PATH:-$OMARCHY_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/bin}"

[[ -e $marker ]] && exit 0
"$detector" >/dev/null || exit 0

sudo env \
  PATH="$system_path" \
  OMARCHY_IMAC20_AMDGPU_LIMINE_CONF="${OMARCHY_IMAC20_AMDGPU_LIMINE_CONF:-/etc/limine-entry-tool.d/imac20-amdgpu-uclk.conf}" \
  OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT="${OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT:-/etc/systemd/system/omarchy-imac20-amdgpu-uclk.service}" \
  bash "$OMARCHY_PATH/install/hardware/apple/fix-imac20-amdgpu-uclk.sh"
sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$marker"
