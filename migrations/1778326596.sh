set -e

echo "Install speech-dispatcher and espeak-ng for text-to-speech support"

omarchy-pkg-add speech-dispatcher espeak-ng

SPEECHD_CONFIG="$HOME/.config/speech-dispatcher/speechd.conf"

if [[ ! -f "$SPEECHD_CONFIG" ]]; then
  mkdir -p "$HOME/.config/speech-dispatcher"
  cp "$OMARCHY_PATH/config/speech-dispatcher/speechd.conf" "$SPEECHD_CONFIG"
fi
