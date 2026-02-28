#!/bin/bash
for iface in /sys/class/net/*/wireless; do
  iface="$(basename "$(dirname "$iface")")"
  iw dev "$iface" set power_save "$1" 2>/dev/null
done
