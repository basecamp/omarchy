echo "Keep the speaker sink open on the Dell XPS 14 to stop one side dropping out"

# The XPS 14 (SKU 0DB9) has four cs35l56 amps split across two SoundWire links,
# two per side. Link 3 intermittently loses the bus when it re-enumerates on
# resume from idle ("soundwire_intel.link.3: Bus clash for control word"), and
# its two amps then stay silent for the life of the open PCM -- playback
# continues from one side only until the stream is reopened. WirePlumber
# suspends an idle node after 5s, so an ordinary listening session power-cycles
# the link constantly. New installs get the drop-in from
# install/user/hardware/dell/fix-xps14-speaker-dropout.sh; place it here for
# installs that already exist.
if omarchy-hw-sku "0DB9"; then
  config="wireplumber/wireplumber.conf.d/dell-xps14-speaker-no-suspend.conf"
  dest="$HOME/.config/$config"

  if [[ ! -f $dest ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$OMARCHY_PATH/default/$config" "$dest"

    # Apply it now rather than leaving the fix inert until the next login. A
    # session that has no running wireplumber to restart is not an error here.
    systemctl --user restart wireplumber.service || true
  fi
fi
