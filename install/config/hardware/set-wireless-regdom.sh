#!/bin/bash

# First check that wireless-regdb is there
if [ ! -f "/etc/conf.d/wireless-regdom" ]; then
  exit 1
fi

# If the region is already set, we're done
unset WIRELESS_REGDOM
. /etc/conf.d/wireless-regdom
if [ -n "${WIRELESS_REGDOM}" ]; then
  exit 0
fi

# Get the current timezone
if command -v timedatectl &> /dev/null; then
  TIMEZONE=$(timedatectl | grep 'Time zone' | awk '{print $3}')
else
  exit 1
fi

if [ ! -f "/usr/share/zoneinfo/zone.tab" ]; then
  exit 1
fi

# Get the two letter country code using the timezone
COUNTRY=$(awk -v tz="$TIMEZONE" '$3 == tz {print $1; exit}' /usr/share/zoneinfo/zone.tab)

# Append it to the wireless-regdom conf file that is used at boot
echo "WIRELESS_REGDOM=\"$COUNTRY\"" >> /etc/conf.d/wireless-regdom

# Also set it one off now
if command -v iw &> /dev/null; then
  iw reg set ${COUNTRY}
fi

exit 0

