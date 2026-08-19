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

emit_image() {
  local mime="$1"
  local ext tmp hash file

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

  jq -cn --arg mime "$mime" --arg path "$file" --arg captured_at "$(date +'%A %H:%M')" \
    '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

emit_text() {
  perl -MEncode=decode,FB_CROAK -MJSON::PP=encode_json -0777 -e '
    my $raw = <STDIN>;
    exit unless length $raw;

    my $encoding;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif (length($raw) % 2 == 0) {
      my @bytes = unpack("C*", $raw);
      my ($even_nuls, $odd_nuls) = (0, 0);
      for my $index (0 .. $#bytes) {
        next unless $bytes[$index] == 0;
        if ($index % 2 == 0) {
          $even_nuls++;
        } else {
          $odd_nuls++;
        }
      }

      # BOM-less UTF-16 is indistinguishable from NUL-separated bytes. Decode
      # only when at least three quarters of the code units have consistent
      # padding, while allowing Unicode punctuation and other non-ASCII units.
      my $units = @bytes / 2;
      if ($odd_nuls > $even_nuls && $odd_nuls * 4 >= $units * 3) {
        $encoding = "UTF-16LE";
      } elsif ($even_nuls > $odd_nuls && $even_nuls * 4 >= $units * 3) {
        $encoding = "UTF-16BE";
      }
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
