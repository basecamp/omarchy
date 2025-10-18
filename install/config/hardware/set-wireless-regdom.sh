# First check that wireless-regdb is there
if [ -f "/etc/conf.d/wireless-regdom" ]; then
  unset WIRELESS_REGDOM
  . /etc/conf.d/wireless-regdom
fi

# If the region is already set, we're done
if [ ! -n "${WIRELESS_REGDOM}" ]; then
  # Get the current timezone
  if [ -e "/etc/localtime" ]; then
    TIMEZONE=$(readlink -f /etc/localtime)
    TIMEZONE=${TIMEZONE#/usr/share/zoneinfo/}

    # Some timezones are formatted with the two letter country code at the start
    COUNTRY="${TIMEZONE%%/*}"

    # If we don't have a two letter country, get it from the timezone table
    if [[ ! "$COUNTRY" =~ ^[A-Z]{2}$ ]] && [ -f "/usr/share/zoneinfo/zone.tab" ]; then
      COUNTRY=$(awk -v tz="$TIMEZONE" '$3 == tz {print $1; exit}' /usr/share/zoneinfo/zone.tab)
    fi

    # Check if we have a two letter country code
    if [[ "$COUNTRY" =~ ^[A-Z]{2}$ ]]; then
      # Append it to the wireless-regdom conf file that is used at boot
      echo "WIRELESS_REGDOM=\"$COUNTRY\"" | sudo tee -a /etc/conf.d/wireless-regdom >/dev/null

      # Also set it one off now
      if command -v iw &>/dev/null; then
        sudo iw reg set ${COUNTRY}
      fi
    fi
  fi
fi
