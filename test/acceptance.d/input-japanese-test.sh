#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

result_file=/tmp/omarchy-acceptance-japanese-input
reader_script=/tmp/omarchy-acceptance-japanese-reader

cleanup() {
  close_windows '^org\.omarchy\.ime-test$'
  rm -f "$result_file" "$reader_script"
}

trap cleanup EXIT

if [[ -n ${OMARCHY_ACCEPTANCE_SUDO_PASSWORD:-} ]]; then
  OMARCHY_ACCEPTANCE_SUDO_PASSWORD="$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" ROOT="$ROOT" SHELL=/bin/bash \
    script -qec 'printf "%s\n" "$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -v 2>/dev/null &&
      if [[ ! -e /var/lib/pacman/sync/core.db ]]; then sudo pacman -Sy --noconfirm; fi &&
      "$ROOT/bin/omarchy-setup-input-mozc"' /dev/null </dev/null
else
  "$ROOT/bin/omarchy-setup-input-mozc"
fi
pacman -Q fcitx5-mozc >/dev/null || fail "Mozc is installed"
pass "Mozc is installed"

group=$(fcitx5-remote -q)
group_info=$(busctl --user --json=short call \
  org.fcitx.Fcitx5 \
  /controller \
  org.fcitx.Fcitx.Controller1 \
  InputMethodGroupInfo \
  s "$group")
jq -e '.data[1] | any(.[0] == "mozc")' <<<"$group_info" >/dev/null || fail "Mozc is registered with Fcitx 5"
pass "Mozc is registered with Fcitx 5"

cat >"$reader_script" <<'EOF'
#!/bin/bash
IFS= read -r value
printf '%s' "$value" > /tmp/omarchy-acceptance-japanese-input
sleep 5
EOF
chmod +x "$reader_script"

launch_app "foot --app-id=org.omarchy.ime-test $reader_script"
wait_until "Japanese input test terminal opens" 15 window_present '^org\.omarchy\.ime-test$'

fcitx5-remote -c
wtype -M ctrl -k space -m ctrl
wtype "nihongo"
wtype -k space
sleep 1
screenshot "success-input-japanese-conversion"
wtype -k Return -k Return

wait_until "Mozc converts romaji to Japanese" 15 grep -Fxq "日本語" "$result_file"

trap - EXIT
cleanup
