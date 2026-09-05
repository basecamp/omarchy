#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cache_home="$tmp/cache"
images="$tmp/images"
stub_bin="$tmp/bin"
mkdir -p "$images" "$stub_bin"

cat >"$stub_bin/vipsthumbnail" <<'EOF'
#!/bin/bash

image="$1"
shift

while (( $# > 0 )); do
  if [[ $1 == "--path" ]]; then
    output=${2%%\[*}
    break
  fi
  shift
done

if [[ -f ${VIPSTHUMBNAIL_FAIL_FILE:-} ]] && grep -Fxq "$image" "$VIPSTHUMBNAIL_FAIL_FILE"; then
  exit 1
fi

[[ -z ${VIPSTHUMBNAIL_CALLS_FILE:-} ]] || printf '%s\n' "$image" >>"$VIPSTHUMBNAIL_CALLS_FILE"
[[ -z ${VIPSTHUMBNAIL_DELAY:-} ]] || sleep "$VIPSTHUMBNAIL_DELAY"
printf 'thumbnail' >"$output"
EOF
chmod +x "$stub_bin/vipsthumbnail"

for name in one two three; do
  printf 'image-%s' "$name" >"$images/$name.png"
done

cache_dir="$cache_home/omarchy/image-selector"
mkdir -p "$cache_dir"

stale_tmp=""
live_lock=""
for image in "$images"/*; do
  signature=$(stat -Lc '%s:%Y' "$image")
  hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
  mkdir "$cache_dir/$hash.jpg.lock"
  touch -m -d '10 minutes ago' "$cache_dir/$hash.jpg.lock"
  stale_tmp="$cache_dir/$hash.jpg.4242.jpg"
  live_lock="$cache_dir/$hash.jpg.lock"
done
printf 'partial' >"$stale_tmp"

cache_key=$(printf '%s' "$images" | md5sum | cut -d ' ' -f 1)
printf '%s\t%s' "$images/one.png" "$cache_dir/missing.jpg" >"$cache_dir/$cache_key.rows"
printf 'v2\n%s:%s\n' "$images" "$(stat -Lc '%Y' "$images")" >"$cache_dir/$cache_key.signature"
printf 'v1\n%s:%s\n' "$images" "$(stat -Lc '%Y' "$images")" >"$cache_dir/$cache_key.fast-signature"

PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$images"

(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 3 )) ||
  fail "image menu recovers thumbnails from stranded locks"
(( $(awk 'END { print NR }' "$cache_dir/$cache_key.rows") == 3 )) ||
  fail "image menu rebuilds every row after cache invalidation"
[[ $(head -n 1 "$cache_dir/$cache_key.signature") == "v3" ]] ||
  fail "image menu invalidates stale row caches"
[[ ! -e $stale_tmp ]] ||
  fail "image menu clears partial thumbnails left by killed generators"
pass "image menu recovers stranded locks and stale rows"

rm -rf "$cache_home"
mkdir -p "$cache_dir"
mkdir "$live_lock"

PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$images"

(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 2 )) ||
  fail "image menu skips a thumbnail whose fresh legacy lock may still be owned"
[[ -d $live_lock ]] ||
  fail "image menu leaves a fresh legacy lock directory alone"
[[ ! -e $cache_dir/$cache_key.rows ]] ||
  fail "image menu does not cache rows while a legacy generator holds a lock"
pass "image menu respects a live legacy generator's lock"

rm -rf "$cache_home"
mkdir -p "$cache_home"
printf '%s\n' "$images/two.png" >"$tmp/failures"

PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" VIPSTHUMBNAIL_FAIL_FILE="$tmp/failures" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$images"

cache_dir="$cache_home/omarchy/image-selector"
[[ ! -e $cache_dir/$cache_key.rows ]] || fail "image menu does not cache incomplete rows"
[[ ! -e $cache_dir/$cache_key.signature ]] || fail "image menu does not sign incomplete rows"
[[ ! -e $cache_dir/$cache_key.fast-signature ]] || fail "image menu does not fast-cache incomplete rows"
pass "image menu leaves failed thumbnail batches uncached"

rm "$tmp/failures"
PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$images"

(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 3 )) ||
  fail "image menu retries a previously failed thumbnail"
(( $(awk 'END { print NR }' "$cache_dir/$cache_key.rows") == 3 )) ||
  fail "image menu caches every row after retry"
pass "image menu completes and caches a later retry"

rm -rf "$cache_home"
mkdir -p "$cache_home"
: >"$tmp/calls"

# The delay keeps both runs inside the generation window so the locks are
# actually contended rather than the second run arriving after the first.
pids=()
for run in 1 2; do
  PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
    VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" VIPSTHUMBNAIL_DELAY=0.25 \
    "$ROOT/bin/omarchy-menu-images" --cache-only "$images" &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail "concurrent image menu runs exit cleanly"
done

(( $(wc -l <"$tmp/calls") == 3 )) || fail "image menu serializes concurrent thumbnail generators"

rm -f "$cache_dir"/*.jpg
rm -f "$cache_dir/$cache_key.rows" "$cache_dir/$cache_key.signature" "$cache_dir/$cache_key.fast-signature"
PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$images"

(( $(wc -l <"$tmp/calls") == 6 )) || fail "image menu releases thumbnail locks after generation"
pass "image menu owns locks for exactly one generator lifetime"

# --group-by-dir hands the picker a third column so every image under one
# directory collapses into a single carousel item -- one theme, its preview and
# its backgrounds -- rather than one item per file.
grouped="$tmp/grouped"
mkdir -p "$grouped/nord" "$grouped/rose-pine"
printf 'image' >"$grouped/nord/000-preview.png"
printf 'image' >"$grouped/nord/001-city.png"
printf 'image' >"$grouped/rose-pine/000-preview.png"

rm -rf "$cache_home"
PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
  "$ROOT/bin/omarchy-menu-images" --cache-only --group-by-dir "$grouped/nord" "$grouped/rose-pine"

grouped_key=$(printf '%s\n%s' "$grouped/nord" "$grouped/rose-pine" | md5sum | cut -d ' ' -f 1)
grouped_rows="$cache_dir/$grouped_key.rows"

[[ -f $grouped_rows ]] || fail "image menu caches grouped rows"
(( $(awk 'END { print NR }' "$grouped_rows") == 3 )) || fail "image menu keeps every grouped image as its own row"
[[ $(awk -F '\t' 'NR == 1 { print $3 }' "$grouped_rows") == "nord" ]] ||
  fail "image menu names a grouped row for its directory"
(( $(awk -F '\t' '$3 == "nord"' "$grouped_rows" | wc -l) == 2 )) ||
  fail "image menu groups every image in a directory under that directory"
[[ $(awk -F '\t' 'END { print $3 }' "$grouped_rows") == "rose-pine" ]] ||
  fail "image menu groups each directory separately"
pass "image menu groups rows by directory"

rm -rf "$cache_home"
PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
  "$ROOT/bin/omarchy-menu-images" --cache-only "$grouped/nord" "$grouped/rose-pine"

(( $(awk -F '\t' 'NF == 2' "$grouped_rows" | wc -l) == 3 )) ||
  fail "image menu leaves ungrouped rows at two columns"
pass "image menu only groups rows when asked to"
