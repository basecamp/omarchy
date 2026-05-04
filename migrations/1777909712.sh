echo "Add wiremix name overrides for poorly-tagged GStreamer streams (e.g., Spotify)"

config=~/.config/wiremix/wiremix.toml
[[ -f $config ]] || exit 0

# Each rule is checked by its own unique match line so existing user overrides
# (for unrelated apps) are preserved and don't suppress these additions.

if ! grep -qF '"client:application.name" = "spotify"' "$config"; then
  cat <<'EOF' >>"$config"

# Spotify on Linux uses GStreamer for playback and doesn't override the
# pulsesink stream-properties, so its PipeWire node inherits the default
# appsrc element name "audio-src". The default wiremix template only reads
# node-level properties, so Spotify shows up as "audio-src: audio-src".
# The client-level application.name is set correctly, so we resolve through
# that. Override matching is first-wins: keep Spotify above the generic rule.
[[names.overrides]]
types = [ "stream" ]
matches = [ { "client:application.name" = "spotify" } ]
templates = [ "Spotify" ]
EOF
fi

if ! grep -qF '"node:media.name" = "audio-src"' "$config"; then
  cat <<'EOF' >>"$config"

# Catch-all for any other GStreamer pipeline that ships with the same
# untagged "audio-src" media name.
[[names.overrides]]
types = [ "stream" ]
matches = [ { "node:media.name" = "audio-src" } ]
templates = [ "{client:application.name}" ]
EOF
fi
