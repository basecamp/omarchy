#!/bin/bash

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
mkdir -p "$IMAGE_DIR"

types=$(wl-paste --list-types 2>/dev/null || true)

emit_image() {
  local mime="$1"
  local ext="$2"
  local tmp=""
  local hash=""
  local file=""

  tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
  if ! wl-paste --type "$mime" > "$tmp" 2>/dev/null || [[ ! -s $tmp ]]; then
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

  jq -cn --arg mime "$mime" --arg path "$file" '{type:"image", mime:$mime, path:$path}'
}

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
  wl-paste --type text --no-newline 2>/dev/null | jq -Rs 'select(length > 0) | {type:"text", text:.}'
fi
