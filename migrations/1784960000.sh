echo "Install the speaker tuning for this laptop, if one ships for it"

# Speaker tunings are PipeWire filter-chain drop-ins gated on a hardware
# predicate, so this is a no-op on machines without one. The limiter is an LV2
# plugin and the graph will not instantiate without it.

if omarchy-audio-tuning match >/dev/null 2>&1; then
  omarchy-pkg-add lsp-plugins-lv2
  omarchy-audio-tuning on
fi
