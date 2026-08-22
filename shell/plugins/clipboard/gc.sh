#!/bin/bash

# Deletes captured clipboard images that no history entry references anymore
# (deleted, evicted, or cleared entries would otherwise leave their files on
# disk forever). Invoked by the plugin after every history save.

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
HISTORY="$STATE_DIR/clipboard-history.json"

[[ -d $IMAGE_DIR ]] || exit 0

declare -A referenced=()
if [[ -f $HISTORY ]]; then
  while IFS= read -r path; do
    [[ -n $path ]] && referenced["$path"]=1
  done < <(jq -r '.[]? | select(.type == "image") | .path // empty' "$HISTORY" 2>/dev/null || true)
fi

# Only touch files older than 10 minutes: capture.sh writes the image before
# its history entry lands (OCR runs in between), so a fresh file can be
# unreferenced while its entry is still in flight.
while IFS= read -r -d '' file; do
  [[ ${referenced["$file"]+x} ]] && continue
  rm -f -- "$file"
done < <(find "$IMAGE_DIR" -maxdepth 1 -type f -mmin +10 -print0)
