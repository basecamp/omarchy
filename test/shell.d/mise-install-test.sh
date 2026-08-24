#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub_bin="$tmpdir/bin"
mkdir -p "$home" "$stub_bin"

# Stands in for the real mise so a generated wrapper can be run and asked what
# arguments it passed on.
cat >"$stub_bin/mise" <<'SH'
#!/bin/bash

printf 'mise' >>"$OMARCHY_MISE_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_MISE_TEST_LOG"
done
printf '\n' >>"$OMARCHY_MISE_TEST_LOG"
SH
chmod +x "$stub_bin/mise"

install_wrapper() {
  HOME="$home" "$ROOT/bin/omarchy-mise-install" "$@"
}

# The ordinary case still works, and every call site in install/user/mise.sh
# passes names of this shape.
install_wrapper npm:playwright playwright >/dev/null
[[ -x $home/.local/bin/playwright ]] ||
  fail "a normal install writes an executable wrapper"

log="$tmpdir/normal.log"
: >"$log"
OMARCHY_MISE_TEST_LOG="$log" PATH="$stub_bin:$PATH" "$home/.local/bin/playwright" >/dev/null
grep -Fqx $'mise\tuse\t-g\t--quiet\tnpm:playwright' "$log" ||
  fail "the wrapper asks mise for the package it was given" "$(cat "$log")"

pass "a normal install writes a wrapper that names its package"

# A package name is data. Quoted with %q it reaches mise as one argument
# instead of being read as shell source when the wrapper runs.
install_wrapper 'npm:pkg$(touch '"$tmpdir"'/PWNED)end' hostile >/dev/null

log="$tmpdir/hostile.log"
: >"$log"
OMARCHY_MISE_TEST_LOG="$log" PATH="$stub_bin:$PATH" "$home/.local/bin/hostile" >/dev/null

[[ -e $tmpdir/PWNED ]] &&
  fail "a package name with shell characters does not run when the wrapper does" \
    "wrapper: $(cat "$home/.local/bin/hostile")"

grep -Fqx $'mise\tuse\t-g\t--quiet\tnpm:pkg$(touch '"$tmpdir"'/PWNED)end' "$log" ||
  fail "the package reaches mise whole" "$(cat "$log")"

pass "a package name with shell characters reaches mise as one argument"

# The command name is a file name under ~/.local/bin. These shapes escape it,
# hide it, make something that reads as an option, or carry characters that have
# no business in a file name. Labelled so a newline in the value does not end up
# inside the test output.
refused=(
  "a slash" "../escaped"
  "a leading dot" ".hidden"
  "a leading dash" "-dash"
  "a newline" $'with\nnewline'
  "a tab" $'with\ttab'
)

for (( i = 0; i < ${#refused[@]}; i += 2 )); do
  label=${refused[i]}
  name=${refused[i + 1]}

  if install_wrapper somepkg "$name" >/dev/null 2>"$tmpdir/err"; then
    fail "a command name with $label is refused"
  fi
  grep -Fq 'is not usable as a command name' "$tmpdir/err" ||
    fail "the refusal says why for a command name with $label" "$(cat "$tmpdir/err")"
done

pass "command names that are not plain file names are refused"

# The refusal has to land before the rm, which would otherwise delete the
# escaped path on its way to failing.
victim="$tmpdir/victim"
printf 'keep me\n' >"$victim"
if install_wrapper somepkg "../../../..$victim" >/dev/null 2>&1; then
  fail "an escaping command name is refused"
fi
[[ -f $victim ]] ||
  fail "an escaping command name removes nothing outside ~/.local/bin"

pass "an escaping command name removes nothing outside ~/.local/bin"
