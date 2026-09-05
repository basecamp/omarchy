# Stop one side of the speakers dropping out on the Dell XPS 14 (SKU 0DB9).
#
# The machine has four cs35l56 amps split across two SoundWire links, two per
# side. Link 3 intermittently loses the bus when it re-enumerates on resume from
# idle ("soundwire_intel.link.3: Bus clash for control word"), and its two amps
# then stay silent for the life of the open PCM. Playback continues from one
# side only until the stream is torn down and reopened, so pausing and resuming
# the player clears it -- which is what makes the symptom look intermittent and
# player-specific. The digital path is fine throughout: the sink monitor
# measures correct stereo the whole time.
#
# WirePlumber suspends an idle node after 5s and the amps runtime-suspend after
# 100ms, so an ordinary listening session power-cycles the link constantly and
# keeps rolling the dice. Holding the speaker sink open stops the cycling, at
# the cost of a little idle battery while the sink exists.
if omarchy-hw-sku "0DB9"; then
  mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
  cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/dell-xps14-speaker-no-suspend.conf" ~/.config/wireplumber/wireplumber.conf.d/
fi
