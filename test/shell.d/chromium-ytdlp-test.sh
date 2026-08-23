#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

export PATH="$ROOT/bin:$PATH"

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_command jq

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
manifest_path="$test_home/.config/chromium/NativeMessagingHosts/com.omarchy.ytdlp.json"

HOME="$test_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-ytdlp

[[ -f $manifest_path ]] || fail "yt-dlp native host installer creates fresh Chromium profile root"
pass "yt-dlp native host installer creates fresh Chromium profile root"

jq -e --arg path "$ROOT/bin/omarchy-chromium-ytdlp-host" '
  .name == "com.omarchy.ytdlp" and
  .path == $path and
  (.allowed_origins | index("chrome-extension://dedjgknigfeelejglamclffonmophnfl/"))
' "$manifest_path" >/dev/null
pass "yt-dlp native host manifest uses Omarchy host path and extension id"

parse_result=$(bash -c '
  OMARCHY_PATH="$3"
  source "$1"
  parse_url "$2"
' bash "$ROOT/bin/omarchy-chromium-ytdlp-host" '{"url":"https://example.test/watch?v=\"quoted\"&name=a\\b"}' "$ROOT")

[[ $parse_result == "https://example.test/watch?v=\"quoted\"&name=a\\b" ]] ||
  fail "yt-dlp native host parses escaped JSON URLs" "$parse_result"
pass "yt-dlp native host parses escaped JSON URLs"

bash -c '
  OMARCHY_PATH="$3"
  source "$1"
  valid_url "$2"
' bash "$ROOT/bin/omarchy-chromium-ytdlp-host" "javascript:alert(1)" "$ROOT" &&
  fail "yt-dlp native host rejects non-web URLs"
pass "yt-dlp native host rejects non-web URLs"

host_fn() {
  OMARCHY_PATH="$ROOT" OMARCHY_YTDLP_DIR="${download_dir:-$TMPDIR}" bash -c '
    source "$1"
    shift
    "$@"
  ' bash "$ROOT/bin/omarchy-chromium-ytdlp-host" "$@"
}

host_fn metadata_ok "Night Storm Terminal" ||
  fail "yt-dlp native host accepts a normal video title"
pass "yt-dlp native host accepts a normal video title"

host_fn metadata_ok $'safe\nOMARCHY_FILE\tCLICK' &&
  fail "yt-dlp native host rejects a title containing control characters"
pass "yt-dlp native host rejects a title containing control characters"

download_dir="$TMPDIR/videos"
mkdir -p "$download_dir" "$TMPDIR/outside"
good_file="$download_dir/clip [id].mp4"
printf 'x' >"$good_file"
printf 'x' >"$TMPDIR/outside/secret"
ln -s "$TMPDIR/outside/secret" "$download_dir/escape.mp4"

resolved=$(host_fn resolve_download_file "$good_file")
expected=$(realpath -e -- "$good_file")
[[ $resolved == "$expected" ]] ||
  fail "yt-dlp native host accepts a regular file in the download dir" "$resolved"
pass "yt-dlp native host accepts a regular file in the download dir"

host_fn resolve_download_file "--include=not-a-file" &&
  fail "yt-dlp native host rejects a forged mpv option as the download path"
pass "yt-dlp native host rejects a forged mpv option as the download path"

host_fn resolve_download_file "$TMPDIR/outside/secret" &&
  fail "yt-dlp native host rejects a path outside the download dir"
pass "yt-dlp native host rejects a path outside the download dir"

host_fn resolve_download_file "$download_dir/escape.mp4" &&
  fail "yt-dlp native host rejects a symlink that escapes the download dir"
pass "yt-dlp native host rejects a symlink that escapes the download dir"

host_fn resolve_download_file $'clip.mp4\nOMARCHY_FILE\t--include=not-a-file' &&
  fail "yt-dlp native host rejects a path containing control characters"
pass "yt-dlp native host rejects a path containing control characters"

newline_target="$download_dir/target"$'\n'
printf 'x' >"$newline_target"
# The decoy is the point: dropping the trailing newline lands on a real, different
# file, so a resolver that strips it resolves to the wrong one instead of failing.
printf 'x' >"$download_dir/target"
ln -s "target"$'\n' "$download_dir/newline-link.mp4"

host_fn resolve_download_file "$download_dir/newline-link.mp4" &&
  fail "yt-dlp native host rejects a symlink whose target name ends in a newline"
pass "yt-dlp native host rejects a symlink whose target name ends in a newline"

title=$(host_fn title_from_file "$good_file")
[[ $title == "clip [id]" ]] || fail "yt-dlp native host titles the toast from the filename" "$title"
pass "yt-dlp native host titles the toast from the filename"

dash_title=$(host_fn title_from_file "$download_dir/--include.mp4")
[[ $dash_title == "Video" ]] || fail "yt-dlp native host does not pass a leading-dash title to notify-send" "$dash_title"
pass "yt-dlp native host does not pass a leading-dash title to notify-send"

cmd=$(host_fn playback_command --include=not-a-file)
[[ $cmd == "mpv -- --include=not-a-file" ]] ||
  fail "yt-dlp native host runs mpv with -- before the path" "$cmd"
pass "yt-dlp native host runs mpv with -- before the path"

spaced_cmd=$(host_fn playback_command "$download_dir/a b.mp4")
[[ $spaced_cmd == "mpv -- $download_dir/a\\ b.mp4" ]] ||
  fail "yt-dlp native host shell-quotes the mpv path" "$spaced_cmd"
pass "yt-dlp native host shell-quotes the mpv path"

parse_script="$TMPDIR/parse-ytdlp-lines.sh"
cat >"$parse_script" <<'EOF'
source "$1"
filepath=""
while IFS= read -r line; do
  case $line in
  OMARCHY_FILE*)
    resolved=$(resolve_download_file "${line#OMARCHY_FILE$'\t'}") || continue
    filepath=$resolved
    ;;
  esac
done
printf '%s' "$filepath"
EOF

# A title that ends in a newline closes its own record, so the forged record is the
# last one and the real path lands on a line the loop ignores.
poisoned=$(
  printf '%s\n' \
    $'OMARCHY_FILE\t'"$good_file" \
    $'OMARCHY_FILE\tPlay me\t--include=not-a-file' \
    $'\t'"$good_file" |
    OMARCHY_PATH="$ROOT" OMARCHY_YTDLP_DIR="$download_dir" bash "$parse_script" "$ROOT/bin/omarchy-chromium-ytdlp-host"
)

[[ $poisoned == "$expected" ]] ||
  fail "yt-dlp native host keeps a real file after a forged OMARCHY_FILE record" "$poisoned"
pass "yt-dlp native host keeps a real file after a forged OMARCHY_FILE record"
