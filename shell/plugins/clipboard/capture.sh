#!/bin/bash

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
mkdir -p "$IMAGE_DIR"

types=$(wl-paste --list-types 2>/dev/null || true)

if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

emit_image() {
  local mime="$1"
  local ext="$2"
  local tmp=""
  local hash=""
  local file=""

  tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
  if ! timeout 2s wl-paste --type "$mime" > "$tmp" 2>/dev/null || [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    return 0
  fi

  hash=$(sha256sum "$tmp" | awk '{print $1}')
  file="$IMAGE_DIR/$hash.$ext"
  if [[ -e $file ]]; then
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
  fi

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_image_stream() {
  local mime="$1"
  local ext="$2"
  local tmp=""
  local hash=""
  local file=""

  tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
  cat >"$tmp"
  if [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    return 0
  fi

  hash=$(sha256sum "$tmp" | awk '{print $1}')
  file="$IMAGE_DIR/$hash.$ext"
  if [[ -e $file ]]; then
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
  fi

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text_stream() {
  jq -cRs 'select(length > 0) | {type:"text", text:.}'
}

case "${OMARCHY_CLIPBOARD_WATCH_MIME:-}" in
text) emit_text_stream; exit 0 ;;
image/png) emit_image_stream 'image/png' 'png'; exit 0 ;;
image/jpeg) emit_image_stream 'image/jpeg' 'jpg'; exit 0 ;;
image/webp) emit_image_stream 'image/webp' 'webp'; exit 0 ;;
image/gif) emit_image_stream 'image/gif' 'gif'; exit 0 ;;
image/bmp) emit_image_stream 'image/bmp' 'bmp'; exit 0 ;;
image/tiff) emit_image_stream 'image/tiff' 'tiff'; exit 0 ;;
esac

if grep -qx 'image/png' <<<"$types"; then
  emit_image 'image/png' 'png'
elif grep -qx 'image/jpeg' <<<"$types"; then
  emit_image 'image/jpeg' 'jpg'
elif grep -qx 'image/webp' <<<"$types"; then
  emit_image 'image/webp' 'webp'
elif grep -qx 'image/gif' <<<"$types"; then
  emit_image 'image/gif' 'gif'
elif grep -qx 'image/bmp' <<<"$types"; then
  emit_image 'image/bmp' 'bmp'
elif grep -qx 'image/tiff' <<<"$types"; then
  emit_image 'image/tiff' 'tiff'
elif grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  wl-paste --type text --no-newline 2>/dev/null | jq -cRs 'select(length > 0) | {type:"text", text:.}'
fi
