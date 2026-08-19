#!/bin/bash

# Captures the current clipboard as a JSON entry on stdout. In watch mode,
# wl-paste invokes this with the payload on stdin and the mime as $1. Without
# arguments, it snapshots the current selection itself.

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
IMAGE_DIR="$STATE_DIR/clipboard-images"
mkdir -p "$IMAGE_DIR"

types=$(wl-paste --list-types 2>/dev/null || true)

if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

# OCR capped so one text-dense screenshot can't bloat the history JSON.
OCR_MAX_CHARS=4000
SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

# Settings on the plugin's entry in shell.json plugins[]:
#   "ocr": true           enables OCR of captured images (default off)
#   "ocrLang": "eng+deu"  tesseract language(s), default eng
plugin_setting() {
  [[ -f $SHELL_JSON ]] || { printf '%s' "$2"; return; }
  jq -r --arg key "$1" --arg default "$2" \
    '(.plugins // []) | map(select(.id == "omarchy.clipboard")) | first | .[$key] // $default' \
    "$SHELL_JSON" 2>/dev/null || printf '%s' "$2"
}

ocr_image() {
  local file="$1" text="" lang
  [[ $(plugin_setting ocr false) == "true" ]] || return 0
  command -v tesseract >/dev/null 2>&1 || return 0
  lang=$(plugin_setting ocrLang eng)
  text=$(timeout 15s tesseract -l "$lang" "$file" - 2>/dev/null | tr -s '[:space:]' ' ') || true
  text="${text# }"
  text="${text% }"
  printf '%s' "${text:0:OCR_MAX_CHARS}"
}

emit_image() {
  local mime="$1"
  local ext tmp hash file ocr

  ext=${mime#image/}
  [[ $ext == jpeg ]] && ext=jpg

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

  ocr=$(ocr_image "$file")

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" --arg ocr "$ocr" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}
     + (if ($ocr | length) > 0 then {ocrText:$ocr} else {} end)'
}

emit_text() {
  perl -MEncode=decode,FB_CROAK -MJSON::PP=encode_json -0777 -e '
    my $raw = <STDIN>;
    exit unless length $raw;

    my $encoding;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif ($raw =~ /^(?:[^\0]\0)+\z/s) {
      # BOM-less UTF-16 is indistinguishable from NUL-separated bytes, so only
      # decode the consistent whole-payload pattern seen from affected apps.
      $encoding = "UTF-16LE";
    } elsif ($raw =~ /^(?:\0[^\0])+\z/s) {
      $encoding = "UTF-16BE";
    }

    my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK) } : undef;
    $text = decode("UTF-8", $raw) unless defined $text;
    print "{\"type\":\"text\",\"text\":", encode_json($text), "}\n";
  '
}

case "${1:-}" in
text) emit_text; exit 0 ;;
image/*) emit_image "$1"; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
