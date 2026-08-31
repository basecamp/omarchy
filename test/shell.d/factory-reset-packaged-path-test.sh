#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

helper="$ROOT/bin/omarchy-system-factory-reset"

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-system-factory-reset' "$helper" >/dev/null ||
  fail "omarchy-system-factory-reset names the packaged path"

grep -F 'exec sudo env "${gum_env[@]}" "$PACKAGED_PATH" "$@"' "$helper" >/dev/null ||
  fail "omarchy-system-factory-reset elevates the packaged path, not \$0"

if grep -F 'exec sudo env "${gum_env[@]}" "$0" "$@"' "$helper" >/dev/null; then
  fail "omarchy-system-factory-reset no longer sudoes \$0"
fi

pass "factory-reset elevates /usr/bin/omarchy-system-factory-reset"

if (( EUID == 0 )); then
  pass "running as root; skipping the elevation checks, which would start a real reset"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

copy="$stub_bin/omarchy-system-factory-reset"
cp "$helper" "$copy"
chmod +x "$copy"

elevation_log="$test_tmp/elevation"
: >"$elevation_log"

# A copy on PATH is how a writable directory in front of /usr/bin would start
# this. $0 is that copy. sudo must still be asked to run the packaged file.
env -i HOME="$test_tmp" USER=tester PATH="$stub_bin:/usr/bin" \
  ELEVATION_LOG="$elevation_log" \
  "$copy"

got=$(cat "$elevation_log")
[[ $got == "sudo env /usr/bin/omarchy-system-factory-reset" ]] ||
  fail "a writable copy still elevates the packaged path" "got: $got"

pass "a writable copy sudoes /usr/bin/omarchy-system-factory-reset, not itself"

: >"$elevation_log"
env -i HOME="$test_tmp" USER=tester PATH="$stub_bin:/usr/bin" \
  ELEVATION_LOG="$elevation_log" \
  bash -c 'omarchy-system-factory-reset'

got=$(cat "$elevation_log")
[[ $got == "sudo env /usr/bin/omarchy-system-factory-reset" ]] ||
  fail "a PATH lookup still elevates the packaged path" "got: $got"

pass "a PATH lookup sudoes the packaged path"

: >"$elevation_log"
env -i HOME="$test_tmp" USER=tester PATH="$stub_bin:/usr/bin" \
  GUM_FOREGROUND=212 ELEVATION_LOG="$elevation_log" \
  "$copy"

got=$(cat "$elevation_log")
[[ $got == "sudo env GUM_FOREGROUND=212 /usr/bin/omarchy-system-factory-reset" ]] ||
  fail "gum theme vars are still forwarded" "got: $got"

pass "gum theme vars are forwarded on the packaged path"
