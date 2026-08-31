#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

update="$ROOT/bin/omarchy-update-system-pkgs"
retired_handler="$ROOT/bin/omarchy-update-system-pkgs-when-conflicted"

[[ ! -e $retired_handler ]] || fail "the exploitable conflict mover is still shipped"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/tmp" "$test_tmp/root-config" "$test_tmp/attacker"

victim="$test_tmp/root-config/80-root-trigger.rules"
pivot="$test_tmp/attacker/pivot"
printf '%s\n' 'ORIGINAL ROOT CONFIG' >"$victim"
ln -s "$test_tmp/root-config" "$pivot"
original_identity=$(stat -c '%d:%i:%u:%g:%a' "$victim")

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_CALLS"
[[ $* == '/usr/bin/env LC_ALL=C OMARCHY_UPDATE_PACMAN=1 /usr/bin/pacman -Syu --noconfirm' ]] || exit 97
exec "$PACMAN_STUB"
STUB

cat >"$stub_bin/pacman-stub" <<'STUB'
#!/bin/bash
cat >&2 <<EOF
error: failed to commit transaction (conflicting files)
omarchy: $PIVOT exists in filesystem
omarchy: $PIVOT/80-root-trigger.rules exists in filesystem
EOF
exit 73
STUB

for command in mv mkdir install omarchy-update-system-pkgs-when-conflicted; do
  cat >"$stub_bin/$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$MUTATION_LOG"
exit 96
STUB
done
chmod 0755 "$stub_bin"/*

: >"$test_tmp/sudo-calls"
: >"$test_tmp/mutations"
set +e
env \
  PACMAN_STUB="$stub_bin/pacman-stub" \
  PIVOT="$pivot" \
  SUDO_CALLS="$test_tmp/sudo-calls" \
  MUTATION_LOG="$test_tmp/mutations" \
  TMPDIR="$test_tmp/tmp" \
  PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
  bash "$update" >"$test_tmp/out" 2>"$test_tmp/err"
status=$?
set -e

((status == 73)) || fail "a filesystem conflict does not preserve Pacman's failure status"
[[ $(stat -c '%d:%i:%u:%g:%a' "$victim") == "$original_identity" ]] ||
  fail "the former pivot exploit changed the root configuration identity"
grep -qxF 'ORIGINAL ROOT CONFIG' "$victim" || fail "the former pivot exploit changed root configuration bytes"
[[ -L $pivot ]] || fail "the former pivot exploit moved its attacker-controlled symlink"
[[ ! -s $test_tmp/mutations ]] || fail "a filesystem conflict reached a privileged filesystem mutator" "$(<"$test_tmp/mutations")"
[[ $(wc -l <"$test_tmp/sudo-calls") == 1 ]] || fail "a filesystem conflict authorized more than the original Pacman transaction"
[[ -z $(find "$test_tmp/tmp" -mindepth 1 -print -quit) ]] || fail "the captured diagnostic report was retained"

pass "the original writable-report pivot exploit has no privileged move or restore path"

# Keep the architectural invariant load-bearing: no environment flag, report
# parser, quarantine directory, or overwrite retry may silently reintroduce the
# rejected recovery model.
if rg -n 'OMARCHY_UPDATE_CONFLICT|OMARCHY_UPDATE_RETRY|OMARCHY_REPLACED_DIR|when-conflicted' "$ROOT/bin"; then
  fail "an automatic filesystem-conflict recovery route was reintroduced"
fi
if rg -n -- '--overwrite' "$update"; then
  fail "ordinary package updates regained an overwrite escape hatch"
fi
pass "ordinary updates remain fail-closed at the package ownership boundary"
