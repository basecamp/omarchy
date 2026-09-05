#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-t1-als"
als="$ROOT/bin/omarchy-als-brightness"
fix="$ROOT/install/hardware/apple/fix-t1-als-brightness.sh"
migration="$ROOT/migrations/1788621849.sh"
unit="$ROOT/default/systemd/user/omarchy-als-brightness.service"

assert_hw() {
  local model=$1 expect=$2 als_file=$3 description=$4
  local tmp got
  tmp=$(mktemp)
  printf '%s\n' "$model" >"$tmp"
  if OMARCHY_DMI_PRODUCT_NAME="$tmp" OMARCHY_ALS="$als_file" "$hw"; then
    got=yes
  else
    got=no
  fi
  rm -f "$tmp"
  [[ $got == "$expect" ]] || fail "$description"
  pass "$description"
}

als_ok=$(mktemp)
printf '170\n' >"$als_ok"

assert_hw MacBookPro14,3 yes "$als_ok" "MacBookPro14,3 with ALS is detected"
assert_hw MacBookPro14,2 yes "$als_ok" "MacBookPro14,2 with ALS is detected"
assert_hw MacBookPro13,3 yes "$als_ok" "MacBookPro13,3 with ALS is detected"
assert_hw MacBookPro13,2 yes "$als_ok" "MacBookPro13,2 with ALS is detected"
assert_hw MacBookPro14,1 no "$als_ok" "MacBookPro14,1 is not T1"
assert_hw MacBookPro15,1 no "$als_ok" "MacBookPro15,1 is T2"
assert_hw MacBookPro14,3 no /no/such/als "MacBookPro14,3 without ALS is not detected"
pass "T1 ALS detector is gated on DMI and the IIO node"

grep -Fq 'fix-t1-als-brightness.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the T1 ALS hook"
pass "T1 ALS hook is wired"

grep -Fq 'omarchy-als-brightness.service' "$ROOT/install/user/first-run/enable-user-units.sh" ||
  fail "first-run enables the ALS brightness unit"
pass "first-run enables the ALS brightness unit"

grep -Fq 'ExecStart=/usr/bin/omarchy-als-brightness' "$unit" ||
  fail "user unit starts omarchy-als-brightness"
grep -Fq 'ExecCondition=/usr/bin/omarchy-hw-apple-t1-als' "$unit" ||
  fail "user unit is gated on the T1 ALS detector"
grep -Fq 'ConditionPathExistsGlob=/sys/bus/iio/devices/iio:device*/in_illuminance_input' "$unit" ||
  fail "user unit stays inert without an IIO ALS"
pass "user unit is gated and starts the ALS helper"

[[ -f $migration ]] || fail "T1 ALS migration exists"
! head -1 "$migration" | grep -q '^#!' || fail "migration has no shebang"
grep -Fq 'MacBookPro13,[23]|MacBookPro14,[23]' "$migration" ||
  fail "migration is gated on T1 DMI"
pass "migration is gated and has no shebang"

grep -Fq 'omarchy-als-brightness' "$ROOT/manual/44-mac-support.md" ||
  fail "Mac support chapter documents T1 ALS auto-brightness"
pass "Mac support chapter documents T1 ALS auto-brightness"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp" "$als_ok"' EXIT

mkdir -p "$test_tmp/stub"
printf '818\n' >"$test_tmp/panel"
printf '50\n' >"$test_tmp/kbd"
cat >"$test_tmp/stub/brightnessctl" <<SH
#!/bin/bash
dev=""
while (( \$# > 0 )); do
  case \$1 in
    -d) dev=\$2; shift 2 ;;
    set)
      if [[ \$dev == gmux_backlight ]]; then
        printf '%s\n' "\$2" >"$test_tmp/panel"
      else
        printf '%s\n' "\$2" >"$test_tmp/kbd"
      fi
      exit 0
      ;;
    *) shift ;;
  esac
done
exit 0
SH
cat >"$test_tmp/stub/omarchy-hw-display" <<'SH'
#!/bin/bash
printf 'gmux_backlight\n'
SH
chmod +x "$test_tmp/stub/"*

printf 'open\n' >"$test_tmp/lid"
PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_ALS="$als_ok" \
  OMARCHY_ALS_PANEL=gmux_backlight \
  OMARCHY_ALS_KBD=spi::kbd_backlight \
  OMARCHY_ALS_LID="$test_tmp/lid" \
  OMARCHY_ALS_ONCE=1 \
  "$als"

[[ $(cat "$test_tmp/panel") == 42% ]] || fail "ALS 170 maps panel to 42%" "panel=$(cat "$test_tmp/panel")"
[[ $(cat "$test_tmp/kbd") == 81 ]] || fail "ALS 170 maps keyboard to 81" "kbd=$(cat "$test_tmp/kbd")"
pass "ALS 170 sets panel 42% and keyboard 81"

printf '0\n' >"$als_ok"
PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_ALS="$als_ok" \
  OMARCHY_ALS_PANEL=gmux_backlight \
  OMARCHY_ALS_KBD=spi::kbd_backlight \
  OMARCHY_ALS_LID="$test_tmp/lid" \
  OMARCHY_ALS_ONCE=1 \
  "$als"
[[ $(cat "$test_tmp/panel") == 8% ]] || fail "dark ALS keeps an 8% panel floor" "panel=$(cat "$test_tmp/panel")"
[[ $(cat "$test_tmp/kbd") == 255 ]] || fail "dark ALS turns the keyboard fully on" "kbd=$(cat "$test_tmp/kbd")"
pass "dark ALS floors the panel and lights the keyboard"

printf '400\n' >"$als_ok"
PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_ALS="$als_ok" \
  OMARCHY_ALS_PANEL=gmux_backlight \
  OMARCHY_ALS_KBD=spi::kbd_backlight \
  OMARCHY_ALS_LID="$test_tmp/lid" \
  OMARCHY_ALS_ONCE=1 \
  "$als"
[[ $(cat "$test_tmp/kbd") == 0 ]] || fail "bright ALS turns the keyboard off" "kbd=$(cat "$test_tmp/kbd")"
pass "bright ALS turns the keyboard off"

printf 'closed\n' >"$test_tmp/lid"
printf '818\n' >"$test_tmp/panel"
printf '50\n' >"$test_tmp/kbd"
printf '0\n' >"$als_ok"
PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_ALS="$als_ok" \
  OMARCHY_ALS_PANEL=gmux_backlight \
  OMARCHY_ALS_KBD=spi::kbd_backlight \
  OMARCHY_ALS_LID="$test_tmp/lid" \
  OMARCHY_ALS_ONCE=1 \
  "$als"
[[ $(cat "$test_tmp/panel") == 818 ]] || fail "closed lid must not change the panel" "panel=$(cat "$test_tmp/panel")"
[[ $(cat "$test_tmp/kbd") == 50 ]] || fail "closed lid must not change the keyboard" "kbd=$(cat "$test_tmp/kbd")"
pass "closed lid leaves brightness alone"
