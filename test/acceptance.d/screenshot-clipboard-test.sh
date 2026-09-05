#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

provider_pattern="$OMARCHY_PATH/shell/plugins/clipboard/publish-image.py"
previous_providers=$(pgrep -f "$provider_pattern" || true)

omarchy capture screenshot fullscreen copy

wait_until "screenshot clipboard advertises image data" 15 bash -c \
  "wl-paste --list-types | grep -qx image/png"
wait_until "screenshot clipboard advertises a terminal path" 15 bash -c \
  "wl-paste --list-types | grep -qx text/plain"
wait_until "screenshot clipboard advertises a file URI" 15 bash -c \
  "wl-paste --list-types | grep -qx text/uri-list"
wait_until "screenshot clipboard advertises its file-backed marker" 15 bash -c \
  "wl-paste --list-types | grep -qx application/x-omarchy-file-backed-image"

path=$(wl-paste --type text/plain --no-newline)
uri=$(wl-paste --type text/uri-list --no-newline)

[[ -f $path ]] || fail "screenshot clipboard path exists" "$path"
[[ $path == "$HOME/.local/state/omarchy/clipboard-images/"*.png ]] || fail "copy-only screenshot uses clipboard state" "$path"
[[ $uri == "file://$path"$'\r' ]] || fail "screenshot clipboard URI identifies its backing file" "$uri"
cmp -s "$path" <(wl-paste --type image/png) || fail "screenshot clipboard image matches its backing file"
pass "screenshot clipboard representations describe the same image"

provider_pid=""
while read -r candidate; do
  if ! grep -qx "$candidate" <<<"$previous_providers"; then
    provider_pid=$candidate
    break
  fi
done < <(pgrep -f "$provider_pattern" || true)
[[ -n $provider_pid ]] || fail "screenshot clipboard provider remains alive"
pass "screenshot clipboard provider remains alive while it owns the selection"

first_provider_pid=$provider_pid
omarchy capture screenshot fullscreen copy
wait_until "a consecutive screenshot replaces its previous provider" 15 bash -c \
  '! kill -0 "$1" 2>/dev/null' _ "$first_provider_pid"

provider_pid=""
provider_count=0
while read -r candidate; do
  if [[ $candidate != "$first_provider_pid" ]] && ! grep -qx "$candidate" <<<"$previous_providers"; then
    provider_pid=$candidate
    ((provider_count += 1))
  fi
done < <(pgrep -f "$provider_pattern" || true)
[[ -n $provider_pid ]] || fail "consecutive screenshot starts a replacement provider"
((provider_count == 1)) || fail "consecutive screenshot leaves exactly one replacement provider" "$provider_count providers"
pass "consecutive screenshots retain exactly the current clipboard owner"

printf 'clipboard replacement' | wl-copy >/dev/null 2>&1
wait_until "screenshot clipboard provider exits after replacement" 15 bash -c \
  '! kill -0 "$1" 2>/dev/null' _ "$provider_pid"
