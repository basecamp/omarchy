#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The kernel check walks the real /usr/lib/modules; without an installed kernel
# there the reboot-required branch is unreachable and there is nothing to test.
installed_kernel=""
for kernel in /usr/lib/modules/*/vmlinuz; do
  [[ -f $kernel ]] || continue
  installed_kernel=$(basename "$(dirname "$kernel")")
  break
done

if [[ -z $installed_kernel ]]; then
  pass "no kernel under /usr/lib/modules; skipping reboot-required checks"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls.log"
home="$test_tmp/home"
state_dir="$home/.local/state/omarchy"
flag="$state_dir/reboot-required"
mkdir -p "$mock_bin" "$state_dir"

cat >"$mock_bin/uname" <<SH
#!/bin/bash

echo "$installed_kernel"
SH

cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash

exit 0
SH

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash

exit 1
SH

# gum records the prompt and declines it, so the script continues past it.
cat >"$mock_bin/gum" <<'SH'
#!/bin/bash

printf 'gum %s\n' "$*" >>"$CALL_LOG"
exit 1
SH

for command in omarchy-system-reboot omarchy-restart-shell; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash

printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
chmod +x "$mock_bin"/*

run_update_restart() {
  : >"$call_log"
  HOME="$home" PATH="$mock_bin:$ROOT/bin:$PATH" CALL_LOG="$call_log" \
    "$ROOT/bin/omarchy-update-restart" >/dev/null
}

prompted_for_reboot() {
  grep -qF 'gum confirm Updates require reboot. Ready?' "$call_log"
}

boot_time=$(awk '/^btime/ {print $2}' /proc/stat)

# A flag older than the current boot was already honored by a reboot that did
# not go through omarchy-system-reboot.
touch -d "@$((boot_time - 60))" "$flag"
run_update_restart

if prompted_for_reboot; then
  fail "reboot-required flag written before the current boot does not prompt"
fi
pass "reboot-required flag written before the current boot does not prompt"

if [[ -e $flag ]]; then
  fail "reboot-required flag written before the current boot is cleared"
fi
pass "reboot-required flag written before the current boot is cleared"

# A flag set since boot, e.g. by a migration in this very update, still prompts.
touch "$flag"
run_update_restart

if ! prompted_for_reboot; then
  fail "reboot-required flag written since boot prompts for a reboot" "$(cat "$call_log")"
fi
pass "reboot-required flag written since boot prompts for a reboot"

if [[ ! -e $flag ]]; then
  fail "declining the prompt keeps the reboot-required flag"
fi
pass "declining the prompt keeps the reboot-required flag"

# No flag, no prompt.
rm -f "$flag"
run_update_restart

if prompted_for_reboot; then
  fail "no reboot-required flag means no prompt"
fi
pass "no reboot-required flag means no prompt"
