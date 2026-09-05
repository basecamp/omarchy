echo "Unload BCM4377 Wi-Fi around sleep on T2 Macs"

# Existing Quattro installs already have mem_sleep_default=deep and t2bce.
# BCM4377b still aborts that S3 attempt. Install the sleep oneshot only when
# the chip is present; leave BCM4364 and non-T2 machines alone. Do not move
# t2bce machines onto s2idle.

machine_marker="${OMARCHY_T2_BCM4377_MARKER:-/var/lib/omarchy/migrations/1788544020}"

[[ ! -e $machine_marker ]] || exit 0

if ! omarchy-hw-t2-bcm4377; then
  exit 0
fi

unit="${OMARCHY_T2_BCM4377_UNIT:-/etc/systemd/system/omarchy-t2-bcm4377-sleep.service}"
src="${OMARCHY_PATH}/install/hardware/apple/omarchy-t2-bcm4377-sleep.service"
legacy_unit="${OMARCHY_T2_BCM4377_LEGACY_UNIT:-/etc/systemd/system/t2-bcm4377-sleep.service}"

sudo install -Dm644 "$src" "$unit"
sudo systemctl daemon-reload

if [[ -f $legacy_unit ]] &&
  grep -Fqx 'ExecStart=/usr/local/sbin/t2-bcm4377-sleep.sh pre' "$legacy_unit" &&
  grep -Fqx 'ExecStop=/usr/local/sbin/t2-bcm4377-sleep.sh post' "$legacy_unit"; then
  sudo systemctl disable t2-bcm4377-sleep.service
fi

sudo systemctl enable omarchy-t2-bcm4377-sleep.service

# Migrations are tracked per user, but this repair is machine-wide. Write the
# root-owned marker last so interrupted installs retry and other users skip it.
sudo install -Dm644 /dev/null "$machine_marker"
