#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-t2-touchpad.sh"
rule_src="$ROOT/install/hardware/apple/99-omarchy-t2-touchpad.rules"
detector="$ROOT/bin/omarchy-hw-t2"
hardware_all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788537572.sh"

grep -Fq 'ID_INPUT_TOUCHPAD_INTEGRATION' "$rule_src" ||
  fail "udev rule sets touchpad integration"
grep -Fq 'Apple Inc. Apple Internal Keyboard / Trackpad' "$rule_src" ||
  fail "udev rule matches the T2 HID name"
! grep -Fq '/etc/libinput' "$leaf" "$migration" ||
  fail "the workaround leaves administrator libinput overrides alone"
grep -Fq 'omarchy-hw-t2' "$leaf" ||
  fail "leaf gates on the T2 detector"
grep -Fq 'omarchy-hw-t2' "$migration" ||
  fail "migration gates on the T2 detector"
if [[ -f $hardware_all ]]; then
  grep -q 'apple/fix-t2-touchpad.sh' "$hardware_all" ||
    fail "the T2 touchpad leaf runs during hardware setup"
  awk '
    /fix-t2\.sh/ { t2=NR }
    /fix-t2-touchpad\.sh/ { pad=NR }
    END {
      if (!(t2 && pad) || !(t2 < pad))
        exit 1
    }
  ' "$hardware_all" ||
    fail "the T2 touchpad leaf runs after T2 setup"
fi
pass "T2 touchpad files mark the pad internal without local libinput quirks"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '74:00.1 Non-VGA unclassified device [0000]: Apple Inc. T2 Bridge Controller [106b:1801] (rev 01)'
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/install" <<'SH'
#!/bin/bash

printf 'install' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

while [[ ${1:-} == -* ]]; do
  shift
done

src=${1:-}
dest=${2:-}
if [[ -n $src && -n $dest ]]; then
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
fi
SH

cat >"$stub_bin/udevadm" <<'SH'
#!/bin/bash

printf 'udevadm' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_detector() {
  PATH="$stub_bin:$PATH" T2_HARDWARE="$1" "$detector"
}

run_detector 1
pass "detector matches T2"

if run_detector 0; then
  fail "detector ignores non-T2 hardware"
fi
pass "detector ignores non-T2 hardware"

cat >"$stub_bin/omarchy-hw-t2" <<'SH'
#!/bin/bash

(( ${T2_HARDWARE:-0} == 1 ))
SH
chmod +x "$stub_bin/omarchy-hw-t2"

rule="$test_tmp/udev/99-omarchy-t2-touchpad.rules"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_HARDWARE="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_TOUCHPAD_RULE="$rule" \
    bash -euo pipefail "$migration" >/dev/null
}

: >"$calls"
run_migration 1
[[ -f $rule ]] || fail "migration installs the udev rule"
grep -Fq 'ID_INPUT_TOUCHPAD_INTEGRATION' "$rule" ||
  fail "migration copies the packaged udev rule"
grep -Fq $'sudo\tudevadm\tcontrol\t--reload-rules' "$calls" ||
  fail "migration reloads udev rules after install"
grep -Fq $'sudo\tudevadm\ttrigger\t--subsystem-match=input\t--action=change' "$calls" ||
  fail "migration reapplies input rules after install"
pass "migration installs and activates the udev rule on T2"

: >"$calls"
run_migration 1
[[ ! -s $calls ]] || fail "an already repaired T2 install is left unchanged" "$(cat "$calls")"
pass "migration is machine-idempotent"

rm -f "$rule"
: >"$calls"
run_migration 0
[[ ! -e $rule ]] || fail "non-T2 systems get no trackpad rule"
[[ ! -s $calls ]] || fail "non-T2 systems skip the trackpad repair" "$(cat "$calls")"
pass "migration skips unrelated hardware"

run_leaf() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_HARDWARE="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_T2_TOUCHPAD_RULE="$rule" \
    bash -euo pipefail "$leaf" >/dev/null
}

rm -f "$rule"
: >"$calls"
run_leaf 1
[[ -f $rule ]] || fail "installer leaf installs the udev rule"
pass "installer leaf installs the udev rule on T2"

rm -f "$rule"
: >"$calls"
run_leaf 0
[[ ! -e $rule ]] || fail "installer leaf skips machines without T2"
[[ ! -s $calls ]] || fail "installer leaf is silent on unrelated hardware" "$(cat "$calls")"
pass "installer leaf skips unrelated hardware"
