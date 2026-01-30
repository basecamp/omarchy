#!/bin/bash

for bat in /sys/class/power_supply/BAT*; do
  [[ -r "$bat/present" ]] &&
  [[ "$(cat "$bat/present")" == "1" ]] &&
  [[ "$(cat "$bat/type")" == "Battery" ]] &&
  exit 0
done

exit 1
