#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_bin="$tmpdir/bin"
staging="$tmpdir/staging"
rm_log="$tmpdir/rm.log"
mkdir -p "$stub_bin" "$staging"
: >"$rm_log"

real_rm=$(command -v rm)

# Everything omarchy-debug gathers, answering fast and saying nothing that
# matters.
for tool in dmesg inxi journalctl pacman expac comm gum ping curl less; do
  cat >"$stub_bin/$tool" <<'SH'
#!/bin/bash

exit 0
SH
  chmod +x "$stub_bin/$tool"
done

# Only dmesg is elevated here, and its output is the privileged part of the log.
# The marker lets the print check find it without matching on anything else.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'DMESG-MARKER\n'
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/hostname" <<'SH'
#!/bin/bash

printf 'test-host\n'
SH
chmod +x "$stub_bin/hostname"

# Records what the script removes, then removes it for real. An empty staging
# directory on its own would also pass for a script that never staged there,
# which is what the old fixed /tmp path did.
cat >"$stub_bin/rm" <<SH
#!/bin/bash

printf '%s\n' "\$@" >>"$rm_log"
exec "$real_rm" "\$@"
SH
chmod +x "$stub_bin/rm"

# TMPDIR points the staging somewhere this test owns, so the checks below read
# only what this run created.
output=$(TMPDIR="$staging" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-debug" --print 2>/dev/null)

grep -q 'DMESG-MARKER' <<<"$output" ||
  fail "omarchy debug --print still prints what it gathered"
pass "omarchy debug --print still prints what it gathered"

grep -q "$staging/" "$rm_log" ||
  fail "omarchy debug stages under TMPDIR and removes it again" \
    "removed: $(cat "$rm_log")"

left_behind=$(find "$staging" -type f | wc -l)
(( left_behind == 0 )) ||
  fail "omarchy debug leaves no staged log behind" "found: $(find "$staging" -type f)"

pass "omarchy debug stages under TMPDIR and removes it again"

# The staged file used to sit at a fixed name, created under the default umask,
# which is world readable in a directory every local user can reach. Keep both
# commands off any name that can be guessed.
grep -q '^LOG_FILE="/tmp/' "$ROOT/bin/omarchy-debug" &&
  fail "omarchy debug stages its log at a name nobody can guess"
grep -q 'LOG_FILE=$(mktemp' "$ROOT/bin/omarchy-debug" ||
  fail "omarchy debug stages its log with mktemp"
pass "omarchy debug stages its log with mktemp"

for staged in TEMP_LOG SYSTEM_INFO; do
  grep -q "^$staged=\"/tmp/" "$ROOT/bin/omarchy-upload-log" &&
    fail "omarchy-upload-log stages $staged at a name nobody can guess"
  grep -q "$staged=\$(mktemp" "$ROOT/bin/omarchy-upload-log" ||
    fail "omarchy-upload-log stages $staged with mktemp"
done
pass "omarchy-upload-log stages its bundle with mktemp"
