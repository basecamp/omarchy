echo "Skip Chromium's new first-run EULA on machines already on Quattro"

# Chromium 151 flipped MasterPrefs::eula_required from false to true, so an
# unconfigured first run now stops on a blank terms-of-service dialog before the
# browser opens. Omarchy answers that in the seed it writes next to the Chromium
# binary, but that seed is only laid down by a fresh install and by the one-time
# 3.x upgrade, so machines already on Quattro never receive it. Retrofit it here.
#
# The literal is deliberately duplicated rather than sourced: a migration repairs
# the state of its own moment, and must not drift when the seed later changes.

chromium_prefs="/usr/lib/chromium/initial_preferences"
chromium_seed='{"distribution":{"require_eula":false},"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'

if [[ $(cat "$chromium_prefs" 2>/dev/null) != "$chromium_seed" ]]; then
  sudo mkdir -p "$(dirname "$chromium_prefs")"
  echo "$chromium_seed" | sudo tee "$chromium_prefs" >/dev/null
fi
