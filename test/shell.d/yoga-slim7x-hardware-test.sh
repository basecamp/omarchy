#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/install/hardware/lenovo/yoga-slim7x.sh"
starter="$ROOT/install/hardware/lenovo/start-yoga-slim7x-remoteprocs.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

bash -n "$setup" "$starter" || fail "Yoga Slim 7x hardware scripts have valid syntax"

matching="$scratch/matching"
mkdir -p "$matching"
printf 'qcom,x1e80100\0lenovo,yoga-slim7x\0' >"$matching/compatible"
(
  omarchy-hw-qualcomm-soc() { return 0; }
  omarchy-hw-match() { return 1; }
  systemctl() { printf '%s\n' "$*" >>"$matching/systemctl.log"; }

  OMARCHY_YOGA_COMPATIBLE_PATH="$matching/compatible" \
    OMARCHY_YOGA_MODULES_LOAD_DIR="$matching/modules-load.d" \
    OMARCHY_YOGA_MKINITCPIO_DIR="$matching/mkinitcpio.conf.d" \
    OMARCHY_YOGA_LIMINE_CONFIG_DIR="$matching/limine-entry-tool.d" \
    OMARCHY_YOGA_SYSTEMD_DIR="$matching/systemd" \
    source "$setup"
)

grep -Fxq 'scmi-cpufreq' "$matching/modules-load.d/yoga-slim7x.conf" ||
  fail "Yoga Slim 7x setup loads its SCMI CPU-frequency driver"
grep -Fxq 'MODULES+=(i2c-hid-of qrtr ps883x pmic_glink_altmode)' \
  "$matching/mkinitcpio.conf.d/yoga-slim7x-initramfs.conf" ||
  fail "Yoga Slim 7x setup initializes the keyboard and display in the initramfs"
grep -Fq '/usr/lib/firmware/qcom/gen70500_sqe.fw' \
  "$matching/mkinitcpio.conf.d/yoga-slim7x-initramfs.conf" ||
  fail "Yoga Slim 7x setup includes its display firmware in the initramfs"
grep -Fxq 'KERNEL_CMDLINE[default]+=" initcall_blacklist=simpledrm_platform_driver_init"' \
  "$matching/limine-entry-tool.d/yoga-slim7x.conf" ||
  fail "Yoga Slim 7x setup defers display ownership to the native driver"
grep -Fq 'ConditionPathExists=!/etc/modprobe.d/qualcomm-adsp-nofw.conf' \
  "$matching/systemd/yoga-slim7x-remoteprocs.service" ||
  fail "Yoga Slim 7x skips DSP startup when the generic firmware leaf blacklists it"
if grep -Fq 'systemd-udev-settle.service' "$matching/systemd/yoga-slim7x-remoteprocs.service"; then
  fail "Yoga Slim 7x DSP startup does not wait for all udev devices"
fi
grep -Fxq 'enable yoga-slim7x-remoteprocs.service' "$matching/systemctl.log" ||
  fail "Yoga Slim 7x enables its remote processor service"

nonmatching="$scratch/nonmatching"
mkdir -p "$nonmatching"
printf 'qcom,x1e80100\0hp,elitebook-ultra-g1q\0' >"$nonmatching/compatible"
(
  omarchy-hw-qualcomm-soc() { return 0; }
  omarchy-hw-match() { return 1; }
  systemctl() { fail "nonmatching Qualcomm hardware does not enable Yoga services"; }

  OMARCHY_YOGA_COMPATIBLE_PATH="$nonmatching/compatible" \
    OMARCHY_YOGA_MODULES_LOAD_DIR="$nonmatching/modules-load.d" \
    OMARCHY_YOGA_MKINITCPIO_DIR="$nonmatching/mkinitcpio.conf.d" \
    OMARCHY_YOGA_LIMINE_CONFIG_DIR="$nonmatching/limine-entry-tool.d" \
    OMARCHY_YOGA_SYSTEMD_DIR="$nonmatching/systemd" \
    source "$setup"
)

[[ ! -e $nonmatching/modules-load.d/yoga-slim7x.conf ]] ||
  fail "nonmatching Qualcomm hardware does not get Yoga CPU setup"
[[ ! -e $nonmatching/mkinitcpio.conf.d/yoga-slim7x-initramfs.conf ]] ||
  fail "nonmatching Qualcomm hardware does not get Yoga initramfs setup"
[[ ! -e $nonmatching/limine-entry-tool.d/yoga-slim7x.conf ]] ||
  fail "nonmatching Qualcomm hardware does not get Yoga boot parameters"
[[ ! -e $nonmatching/systemd/yoga-slim7x-remoteprocs.service ]] ||
  fail "nonmatching Qualcomm hardware does not get Yoga services"

remoteprocs="$scratch/remoteproc"
mkdir -p "$remoteprocs/remoteproc0" "$remoteprocs/remoteproc1" "$remoteprocs/remoteproc2"
printf 'qcom/x1e80100/LENOVO/83ED/qcadsp8380.mbn\n' >"$remoteprocs/remoteproc0/firmware"
printf 'offline\n' >"$remoteprocs/remoteproc0/state"
printf 'qcom/x1e80100/LENOVO/83ED/qccdsp8380.mbn\n' >"$remoteprocs/remoteproc1/firmware"
printf 'offline\n' >"$remoteprocs/remoteproc1/state"
printf 'unrelated.mbn\n' >"$remoteprocs/remoteproc2/firmware"
printf 'offline\n' >"$remoteprocs/remoteproc2/state"

OMARCHY_YOGA_REMOTEPROC_ROOT="$remoteprocs" \
  OMARCHY_YOGA_REMOTEPROC_ATTEMPTS=1 \
  OMARCHY_YOGA_REMOTEPROC_SLEEP=0 \
  bash "$starter"

[[ $(<"$remoteprocs/remoteproc0/state") == start ]] ||
  fail "Yoga Slim 7x helper starts the audio DSP by firmware identity"
[[ $(<"$remoteprocs/remoteproc1/state") == start ]] ||
  fail "Yoga Slim 7x helper starts the compute DSP by firmware identity"
[[ $(<"$remoteprocs/remoteproc2/state") == offline ]] ||
  fail "Yoga Slim 7x helper leaves unrelated remote processors alone"

pass "Yoga Slim 7x adds only its board-specific keyboard, display, CPU and DSP setup"
