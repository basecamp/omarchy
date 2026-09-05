# Suspend power management, S3 deep sleep, and ACPI RTC alarm for ASUS laptops.
#
# On ASUS laptops (ExpertBook, ZenBook, ROG, TUF), sleep and wake behavior require
# specific firmware workarounds:
#
# 1. ACPI RTC Alarm: ASUS motherboards route the RTC CMOS alarm through ACPI
#    Fixed Event handlers rather than legacy IRQ 8. Without rtc_cmos.use_acpi_alarm=1,
#    timer wakeups fail to fire or hang during suspend entry/exit.
#
# 2. DDR5 SPD Sensor Hangs: Systems with DDR5 memory fail async resume when spd5118
#    encounters firmware write-protection (returning error -6 / ENXIO), locking the
#    SMBus and freezing suspend transitions. Blacklisting spd5118 prevents this hang.
#
# 3. S3 Deep Sleep vs Modern Standby (s2idle):
#    While firmware on many modern ASUS laptops still exposes S3 (deep) in
#    /sys/power/mem_sleep, ACPI S3 GPE wake routing for the lid switch (LID0) is
#    often omitted in favor of Modern Standby (s2idle). Enforcing S3 deep sleep on
#    a laptop where the lid switch lacks ACPI S3 wake capability prevents the laptop
#    from waking up when the lid is opened. Furthermore, resuming NVIDIA GPUs from S3
#    on these hybrid platforms frequently fails ACPI D-notifier transitions (status=0x11),
#    causing black screens.
#
#    Therefore, configure S3 (deep) ONLY when firmware exposes "deep" AND the lid
#    switch is registered as an ACPI wakeup device in /proc/acpi/wakeup.
#    Otherwise, default to s2idle so lid-open wake continues to function reliably,
#    and clean up any stale S3 overrides that break lid-open wake.

is_asus() {
  grep -qiE "ASUS|ASUSTeK" /sys/class/dmi/id/sys_vendor 2>/dev/null ||
    omarchy-hw-match "ASUS" ||
    omarchy-hw-match "ROG"
}

if is_asus; then
  # 1. Configure RTC ACPI alarm routing for ASUS motherboards
  mkdir -p /etc/limine-entry-tool.d
  cat > /etc/limine-entry-tool.d/asus-rtc-alarm.conf <<'EOF'
# ASUS motherboards route RTC alarm via ACPI Fixed Event handlers
KERNEL_CMDLINE[default]+=" rtc_cmos.use_acpi_alarm=1"
EOF

  # 2. Blacklist spd5118 if present to prevent DDR5 SMBus suspend/resume freezes
  if lsmod | grep -qw "spd5118" 2>/dev/null || modinfo spd5118 >/dev/null 2>&1; then
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/spd5118.conf <<'EOF'
# Prevent spd5118 async resume failures and SMBus lockups on DDR5 systems
blacklist spd5118
EOF
  fi

  # 3. Check for ACPI S3 deep sleep support AND lid wake capability
  has_s3=$(grep -qw "deep" /sys/power/mem_sleep 2>/dev/null && echo true || echo false)
  has_lid_s3_wake=$(grep -qi "LID" /proc/acpi/wakeup 2>/dev/null && echo true || echo false)

  if [[ $has_s3 == "true" && $has_lid_s3_wake == "true" ]]; then
    mkdir -p /etc/systemd/sleep.conf.d
    cat > /etc/systemd/sleep.conf.d/10-omarchy-asus-deep-sleep.conf <<'EOF'
[Sleep]
MemorySleepMode=deep
EOF

    cat > /etc/limine-entry-tool.d/asus-deep-sleep.conf <<'EOF'
# ASUS S3 deep sleep (firmware provides ACPI S3 lid wake)
KERNEL_CMDLINE[default]+=" mem_sleep_default=deep"
EOF
  else
    # Remove stale or invalid deep sleep overrides that break lid-open wake
    rm -f /etc/systemd/sleep.conf.d/10-omarchy-asus-deep-sleep.conf
    rm -f /etc/systemd/sleep.conf.d/10-mem-sleep-deep.conf
    rm -f /etc/limine-entry-tool.d/asus-deep-sleep.conf
    rm -f /etc/limine-entry-tool.d/mem-sleep.conf
  fi
fi
