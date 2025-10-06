OMARCHY_DESCRIPTION="Wireless Regdom"

omarchy_install() {
  if [ -f "/etc/conf.d/wireless-regdom" ]; then
      unset WIRELESS_REGDOM
      . /etc/conf.d/wireless-regdom
  fi

  if [ ! -n "${WIRELESS_REGDOM}" ]; then
    if [ -e "/etc/localtime" ]; then
      TIMEZONE=$(readlink -f /etc/localtime)
      TIMEZONE=${TIMEZONE#/usr/share/zoneinfo/}

      COUNTRY="${TIMEZONE%%/*}"

      if [[ ! "$COUNTRY" =~ ^[A-Z]{2}$ ]] && [ -f "/usr/share/zoneinfo/zone.tab" ]; then
        COUNTRY=$(awk -v tz="$TIMEZONE" '$3 == tz {print $1; exit}' /usr/share/zoneinfo/zone.tab)
      fi

      if [[ "$COUNTRY" =~ ^[A-Z]{2}$ ]]; then
        echo "WIRELESS_REGDOM=\"$COUNTRY\"" | sudo tee -a /etc/conf.d/wireless-regdom >/dev/null

        if command -v iw &>/dev/null; then
            sudo iw reg set ${COUNTRY}
        fi
      fi
    fi
  fi
}

omarchy_verify() {
  [[ -f /etc/conf.d/wireless-regdom ]] || add_error "Wireless regdom config missing"

  if [[ -f /etc/conf.d/wireless-regdom ]]; then
      grep -q "^WIRELESS_REGDOM=" /etc/conf.d/wireless-regdom || add_error "Wireless regulatory domain not configured"
  fi
}
