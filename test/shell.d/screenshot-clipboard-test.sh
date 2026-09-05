#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/bin" "$TMPDIR/home" "$TMPDIR/screenshots" "$TMPDIR/state"

cat >"$TMPDIR/bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "getoption" ]]; then
  printf '{"int":0}\n'
fi
SH

cat >"$TMPDIR/bin/omarchy-capture-region" <<'SH'
#!/bin/bash
printf '\n10,20 300x200\n'
SH

cat >"$TMPDIR/bin/grim" <<'SH'
#!/bin/bash
[[ ${GRIM_FAIL:-0} == "1" ]] && exit 1
printf '\211PNG\r\n\032\nscreenshot-data' >"${*: -1}"
SH

cat >"$TMPDIR/bin/setsid" <<'SH'
#!/bin/bash
[[ $1 == "-f" ]] && shift
printf '%s\n' "$*" >"$PUBLISH_LOG"
printf '%s' "${*: -1}" >"$PUBLISHED_PATH"
SH

cat >"$TMPDIR/bin/wl-paste" <<'SH'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf 'image/png\ntext/plain\napplication/x-omarchy-file-backed-image\n'
elif [[ $1 == "--type" && $2 == "text/plain" ]]; then
  cat "$PUBLISHED_PATH"
fi
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/"*

run_screenshot() {
  local processing="$1"
  PUBLISH_LOG="$TMPDIR/publish" \
    PUBLISHED_PATH="$TMPDIR/published-path" \
    HOME="$TMPDIR/home" \
    XDG_STATE_HOME="$TMPDIR/state" \
    OMARCHY_SCREENSHOT_DIR="$TMPDIR/screenshots" \
    PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-capture-screenshot" region "$processing"
}

slurp_path=$(run_screenshot slurp)
[[ -f $slurp_path ]] || fail "screenshot slurp saves its image"
[[ $(<"$TMPDIR/published-path") == "$slurp_path" ]] || fail "screenshot slurp publishes its saved file"
grep -Fq "publish-image.py image/png $slurp_path" "$TMPDIR/publish" || fail "screenshot slurp uses the file-backed publisher"
pass "screenshot slurp publishes its saved image with file-backed representations"

rm -f "$TMPDIR/publish" "$TMPDIR/published-path"
run_screenshot copy
copy_path=$(<"$TMPDIR/published-path")
[[ $copy_path == "$TMPDIR/state/omarchy/clipboard-images/"*.png ]] || fail "screenshot copy stores its backing file in clipboard state"
[[ -f $copy_path && $(<"$copy_path") == $'\x89PNG\r\n\x1a\nscreenshot-data' ]] || fail "screenshot copy preserves captured image bytes"
grep -Fq "publish-image.py image/png $copy_path" "$TMPDIR/publish" || fail "screenshot copy uses the file-backed publisher"
pass "screenshot copy publishes a state-backed image"

rm -f "$TMPDIR/publish" "$TMPDIR/published-path"
save_path=$(run_screenshot save)
[[ -f $save_path ]] || fail "screenshot save writes its image"
[[ ! -e $TMPDIR/publish && ! -e $TMPDIR/published-path ]] || fail "screenshot save leaves the clipboard untouched"
pass "screenshot save leaves the clipboard untouched"

if GRIM_FAIL=1 run_screenshot copy; then
  fail "failed screenshot copy removes its temporary image"
fi
shopt -s nullglob
temporary_images=("$TMPDIR/state/omarchy/clipboard-images"/clipboard.*)
(( ${#temporary_images[@]} == 0 )) || fail "failed screenshot copy removes its temporary image"
pass "failed screenshot copy removes its temporary image"
