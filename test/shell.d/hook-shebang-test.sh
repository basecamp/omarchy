#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
hooks_dir="$test_home/.config/omarchy/hooks"
mkdir -p "$hooks_dir/theme-set.d"

run_hook_command() {
  HOME="$test_home" "$ROOT/bin/omarchy-hook" "$@"
}

# An executable hook with its own shebang must run through that interpreter,
# not get force-fed to bash. Point the shebang at a stub interpreter and give
# the hook body content that is not valid bash, so a regression back to
# "bash $hook" would fail loudly here instead of silently misinterpreting the
# hook the way ImageMagick's "import" did for a real Python hook.
marker="$test_tmp/interpreter-ran"
stub_interpreter="$test_tmp/stub-interpreter"
cat >"$stub_interpreter" <<SH
#!/bin/bash
printf '%s\n' "\$*" >"$marker"
SH
chmod +x "$stub_interpreter"

shebang_hook="$hooks_dir/theme-set.d/10-shebang.hook"
cat >"$shebang_hook" <<HOOK
#!$stub_interpreter
this is not valid bash: {{{ import fakestuff ;;; }}}
HOOK
chmod +x "$shebang_hook"

run_hook_command theme-set ethereal >"$test_tmp/shebang.out" 2>&1

[[ -f $marker ]] || fail "executable hook runs through its own shebang" "no marker written; output:
$(cat "$test_tmp/shebang.out")"
read -r ran_path ran_args <"$marker"
[[ $ran_path == "$shebang_hook" ]] || fail "executable hook runs through its own shebang" "expected path: $shebang_hook
actual path:    $ran_path"
[[ $ran_args == "ethereal" ]] || fail "executable hook receives its arguments" "expected: ethereal
actual:   $ran_args"
! grep -q "Hook failed" "$test_tmp/shebang.out" || fail "executable hook does not get force-fed to bash" "$(cat "$test_tmp/shebang.out")"
pass "executable hook runs through its own shebang instead of bash"
rm -f "$shebang_hook"

# The flat ~/.config/omarchy/hooks/<name> file is a second dispatch site, and
# reverting it alone leaves every .d assertion above green.
flat_marker="$test_tmp/flat-ran"
flat_stub="$test_tmp/flat-stub-interpreter"
cat >"$flat_stub" <<SH
#!/bin/bash
printf '%s\n' "\$*" >"$flat_marker"
SH
chmod +x "$flat_stub"

flat_hook="$hooks_dir/theme-set"
cat >"$flat_hook" <<HOOK
#!$flat_stub
this is not valid bash: {{{ import fakestuff ;;; }}}
HOOK
chmod +x "$flat_hook"

run_hook_command theme-set ethereal >"$test_tmp/flat.out" 2>&1

[[ -f $flat_marker ]] || fail "executable flat hook runs through its own shebang" "no marker written; output:
$(cat "$test_tmp/flat.out")"
read -r flat_path flat_args <"$flat_marker"
[[ $flat_path == $flat_hook ]] || fail "executable flat hook runs through its own shebang" "expected path: $flat_hook
actual path:    $flat_path"
[[ $flat_args == "ethereal" ]] || fail "executable flat hook receives its arguments" "expected: ethereal
actual:   $flat_args"
pass "executable flat hook runs through its own shebang instead of bash"
rm -f "$flat_hook"

# A plain, non-executable hook (the shape every shipped .sample hook takes
# once a user copies it) must keep running under bash, exactly as before.
plain_marker="$test_tmp/plain-ran"
plain_hook="$hooks_dir/theme-set.d/20-plain.hook"
cat >"$plain_hook" <<HOOK
echo "plain \$1" >"$plain_marker"
HOOK

run_hook_command theme-set ethereal >"$test_tmp/plain.out" 2>&1

[[ -f $plain_marker ]] || fail "non-executable hook still runs under bash" "output:
$(cat "$test_tmp/plain.out")"
[[ $(<"$plain_marker") == "plain ethereal" ]] || fail "non-executable hook receives its arguments" "actual: $(<"$plain_marker")"
pass "non-executable hook still runs under bash"
rm -f "$plain_hook"

# omarchy-hook-install chmods every hook it copies to 755, so a shell hook with
# no shebang at all is a real installed shape. Exec'ing it hits ENOEXEC and
# bash falls back to running it itself, which is what keeps those hooks working.
noshebang_marker="$test_tmp/noshebang-ran"
noshebang_hook="$hooks_dir/theme-set.d/25-noshebang.hook"
cat >"$noshebang_hook" <<HOOK
echo "noshebang \$1" >"$noshebang_marker"
HOOK
chmod +x "$noshebang_hook"

run_hook_command theme-set ethereal >"$test_tmp/noshebang.out" 2>&1

[[ -f $noshebang_marker ]] || fail "executable hook without a shebang still runs under bash" "output:
$(cat "$test_tmp/noshebang.out")"
[[ $(<"$noshebang_marker") == "noshebang ethereal" ]] || fail "executable hook without a shebang receives its arguments" "actual: $(<"$noshebang_marker")"
pass "executable hook without a shebang still runs under bash"
rm -f "$noshebang_hook"

# A failing executable hook is still reported and does not abort the run,
# matching the "|| echo Hook failed" contract for bash hooks. The later hook is
# what proves the run continued rather than stopping after the report.
failing_hook="$hooks_dir/theme-set.d/30-failing.hook"
cat >"$failing_hook" <<HOOK
#!/bin/bash
exit 1
HOOK
chmod +x "$failing_hook"

later_marker="$test_tmp/later-ran"
later_hook="$hooks_dir/theme-set.d/40-later.hook"
cat >"$later_hook" <<HOOK
#!/bin/bash
echo "later \$1" >"$later_marker"
HOOK
chmod +x "$later_hook"

output=$(run_hook_command theme-set ethereal 2>&1)
[[ $output == *"Hook failed: $failing_hook"* ]] || fail "failing executable hook is reported" "actual: $output"
[[ -f $later_marker ]] || fail "a hook after a failing one still runs" "actual: $output"
pass "failing executable hook is reported without aborting the run"
