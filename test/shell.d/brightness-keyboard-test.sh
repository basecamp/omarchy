#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
state="$tmpdir/state"
mkdir -p "$mock_bin"
printf '1\n' >"$state"

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
state=${OMARCHY_TEST_BRIGHTNESS_STATE:?}
saved=${OMARCHY_TEST_BRIGHTNESS_SAVED:?}

device=""
save=0
restore=0
action=""
value=""
while (( $# > 0 )); do
  case "$1" in
    -d)
      device=$2
      shift 2
      ;;
    -sd)
      save=1
      device=$2
      shift 2
      ;;
    -rd)
      restore=1
      device=$2
      shift 2
      ;;
    get)
      action=get
      shift
      ;;
    max)
      action=max
      shift
      ;;
    set)
      action=set
      value=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ $device == "test::kbd_backlight" ]] || exit 1

if (( restore )); then
  cat "$saved" >"$state"
  cat "$state"
  exit 0
fi

if [[ $action == "get" ]]; then
  cat "$state"
  exit 0
fi

if [[ $action == "max" ]]; then
  printf '2\n'
  exit 0
fi

if [[ $action == "set" ]]; then
  if (( save )); then
    cat "$state" >"$saved"
  fi
  printf '%s\n' "$value" >"$state"
  exit 0
fi

exit 1
SH

cat >"$mock_bin/omarchy-osd" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin"/*

saved="$tmpdir/saved"
printf 'unset\n' >"$saved"

run_kbd() {
  OMARCHY_KBD_BACKLIGHT_DEVICE="test::kbd_backlight" \
    OMARCHY_TEST_BRIGHTNESS_STATE="$state" \
    OMARCHY_TEST_BRIGHTNESS_SAVED="$saved" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-brightness-keyboard" "$@"
}

printf '1\n' >"$state"
run_kbd --no-osd off || fail "keyboard backlight off succeeds on the first call"
[[ $(cat "$saved") == "1" ]] || fail "keyboard backlight off saves the lit level" "saved=$(cat "$saved")"
[[ $(cat "$state") == "0" ]] || fail "keyboard backlight off sets brightness to 0" "state=$(cat "$state")"
pass "keyboard backlight off saves the lit level before blanking"

run_kbd --no-osd off || fail "keyboard backlight off is idempotent"
[[ $(cat "$saved") == "1" ]] || fail "a second off does not overwrite the saved lit level with 0" "saved=$(cat "$saved")"
pass "a second keyboard backlight off keeps the saved lit level"

run_kbd --no-osd restore || fail "keyboard backlight restore succeeds"
[[ $(cat "$state") == "1" ]] || fail "keyboard backlight restore returns the pre-blank level" "state=$(cat "$state")"
pass "keyboard backlight restore returns the pre-blank level"
