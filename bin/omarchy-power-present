#!/bin/bash

# omarchy:summary=Returns true if external power is connected.

power_supply_path="${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"

for supply in "$power_supply_path"/*; do
  [[ -r $supply/online && -r $supply/type ]] || continue
  type=$(<"$supply/type")
  [[ $type == "Mains" || $type == "USB" ]] || continue
  [[ $(<"$supply/online") == "1" ]] && exit 0
done

exit 1
