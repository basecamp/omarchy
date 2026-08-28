# Lenovo Yoga Slim 7x (14Q8X9 / 83ED) board-specific setup.

yoga_slim7x_compatible=""
compatible_path=${OMARCHY_YOGA_COMPATIBLE_PATH:-/sys/firmware/devicetree/base/compatible}
modules_load_dir=${OMARCHY_YOGA_MODULES_LOAD_DIR:-/etc/modules-load.d}
mkinitcpio_dir=${OMARCHY_YOGA_MKINITCPIO_DIR:-/etc/mkinitcpio.conf.d}
limine_config_dir=${OMARCHY_YOGA_LIMINE_CONFIG_DIR:-/etc/limine-entry-tool.d}
systemd_dir=${OMARCHY_YOGA_SYSTEMD_DIR:-/etc/systemd/system}

if [[ -r $compatible_path ]]; then
  yoga_slim7x_compatible=$(tr '\0' '\n' <"$compatible_path")
fi

if omarchy-hw-qualcomm-soc &&
  { grep -qi '^lenovo,yoga-slim7x$' <<<"$yoga_slim7x_compatible" ||
    omarchy-hw-match 'Yoga Slim 7x' || omarchy-hw-match '83ED'; }; then
  echo "Detected Lenovo Yoga Slim 7x, applying board-specific support..."

  # The Yoga exposes its CPU performance domains through SCMI.
  mkdir -p "$modules_load_dir"
  echo "scmi-cpufreq" >"$modules_load_dir/yoga-slim7x.conf"

  # Initialize the internal keyboard and display before disk unlock.
  mkdir -p "$mkinitcpio_dir"
  cat >"$mkinitcpio_dir/yoga-slim7x-initramfs.conf" <<'CONF'
MODULES+=(i2c-hid-of qrtr ps883x pmic_glink_altmode)

for firmware in \
  /usr/lib/firmware/qcom/gen70500_sqe.fw \
  /usr/lib/firmware/qcom/gen70500_gmu.bin \
  /usr/lib/firmware/qcom/x1e80100/LENOVO/83ED/qcdxkmsuc8380.mbn; do
  [[ -f $firmware ]] && FILES+=("$firmware")
done
unset firmware
CONF

  mkdir -p "$limine_config_dir"
  cat >"$limine_config_dir/yoga-slim7x.conf" <<'CONF'
KERNEL_CMDLINE[default]+=" initcall_blacklist=simpledrm_platform_driver_init"
CONF

  # Start the board's DSP remote processors.
  mkdir -p "$systemd_dir"
  cat >"$systemd_dir/yoga-slim7x-remoteprocs.service" <<'UNIT'
[Unit]
Description=Start the Lenovo Yoga Slim 7x DSPs
ConditionPathExists=!/etc/modprobe.d/qualcomm-adsp-nofw.conf

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/share/omarchy/install/hardware/lenovo/start-yoga-slim7x-remoteprocs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl enable yoga-slim7x-remoteprocs.service
fi
