notify_update() {
  omarchy-notification-send -u critical -g  "Update System" "Click to update the system." \
    --exec omarchy-launch-floating-terminal-with-presentation omarchy-update
}

notify_wifi() {
  omarchy-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." \
    --exec omarchy-shell shell toggle omarchy.network
}

announce_network() {
  # Ethernet is still negotiating DHCP when the session starts, so probing
  # right away calls a working machine offline. NetworkManager reports startup
  # complete once it has tried every connection it could auto-activate, which
  # is the first moment the answer means anything.
  nm-online -q -s -t 30

  # -x takes that answer as it stands rather than waiting out the timeout, so
  # a laptop with nothing to connect to gets prompted immediately.
  if ! nm-online -q -x -t 30; then
    notify_wifi
    # Nothing to update against until a link lands, so hold that prompt.
    nm-online -q -t 3600 || return
  fi

  # A captive portal answers DHCP and passes nm-online while still blocking the
  # mirrors, so prompting for an update here would only hand the user a failed
  # one. Hold the prompt until sign-in lands rather than dropping it: first run
  # happens once, so returning here would cost this user the prompt for good.
  # omarchy-network-portal-watch.service is already asking them to sign in, and
  # the wait gets the same hour-long budget as the link above.
  portal_waited=0
  while omarchy-network-portal --check; do
    if ((portal_waited >= 3600)); then return; fi
    sleep 30
    ((portal_waited += 30))
  done

  notify_update
}

# Detached, so a slow or absent connection never holds up the rest of first run.
announce_network &
