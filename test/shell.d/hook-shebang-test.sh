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

# A failing executable hook is still reported and does not abort the run,
# matching the "|| echo Hook failed" contract for bash hooks.
failing_hook="$hooks_dir/theme-set.d/30-failing.hook"
cat >"$failing_hook" <<HOOK
#!/bin/bash
exit 1
HOOK
chmod +x "$failing_hook"

output=$(run_hook_command theme-set ethereal 2>&1)
[[ $output == *"Hook failed: $failing_hook"* ]] || fail "failing executable hook is reported" "actual: $output"
pass "failing executable hook is reported without aborting the run"
