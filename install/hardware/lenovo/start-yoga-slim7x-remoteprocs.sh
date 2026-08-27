#!/bin/bash

set -euo pipefail

remoteproc_root=${OMARCHY_YOGA_REMOTEPROC_ROOT:-/sys/class/remoteproc}
attempts=${OMARCHY_YOGA_REMOTEPROC_ATTEMPTS:-30}
sleep_seconds=${OMARCHY_YOGA_REMOTEPROC_SLEEP:-1}

for ((attempt = 1; attempt <= attempts; attempt++)); do
  adsp_started=0
  shopt -s nullglob

  for state_file in "$remoteproc_root"/remoteproc*/state; do
    remoteproc=${state_file%/state}
    [[ -r $remoteproc/firmware && -r $state_file ]] || continue

    firmware=$(tr -d '\0\n' <"$remoteproc/firmware")
    case "$firmware" in
      *qcadsp*) kind=ADSP ;;
      *qccdsp*) kind=CDSP ;;
      *) continue ;;
    esac

    if [[ $(<$state_file) == running ]]; then
      echo "Yoga Slim 7x: $kind is already running"
      [[ $kind == ADSP ]] && adsp_started=1
    elif [[ -w $state_file ]] && printf 'start\n' >"$state_file"; then
      echo "Yoga Slim 7x: started $kind"
      [[ $kind == ADSP ]] && adsp_started=1
    else
      echo "Yoga Slim 7x: could not start $kind ($firmware)" >&2
    fi
  done

  ((adsp_started)) && exit 0
  sleep "$sleep_seconds"
done

echo "Yoga Slim 7x: audio DSP did not appear or could not be started" >&2
exit 1
