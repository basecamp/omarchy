#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/install/hardware/lenovo/yoga-slim7x.sh"
starter="$ROOT/install/hardware/lenovo/start-yoga-slim7x-remoteprocs.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

bash -n "$setup" "$starter" || fail "Yoga Slim 7x hardware scripts have valid syntax"
grep -Fq 'MODULES+=(i2c-hid-of)' "$setup" ||
  fail "Yoga Slim 7x setup keeps the internal keyboard in the initramfs"
grep -Fq 'scmi-cpufreq' "$setup" ||
  fail "Yoga Slim 7x setup loads its SCMI CPU-frequency driver"

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

pass "Yoga Slim 7x adds only its board-specific keyboard, CPU and DSP setup"
