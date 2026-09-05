#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

panel="$ROOT/shell/plugins/panels/disk-speedtest/Panel.qml"

grep -Fq 'parts[0] === "write" || parts[0] === "stage"' "$panel" ||
  fail "disk speedtest panel treats staging samples as write-dial input"
grep -Fq 'root.phase === "write" || root.phase === "stage"' "$panel" ||
  fail "disk speedtest panel keeps the write dial live during staging"
grep -Fq 'phase = ""' "$panel" ||
  fail "disk speedtest panel starts with no phase so the read dial is not live at 0"
pass "disk speedtest panel treats staging samples as live write-dial input"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub="$tmpdir/bin"
stat_file="$tmpdir/stat"
mkdir -p "$stub" "$tmpdir/chunk" "$tmpdir/target"
# 11 kernel fields; write sectors are field 7 (0-based index 6).
printf '0 0 0 0 0 0 0 0 0 0 0\n' >"$stat_file"
printf '0\n' >"$tmpdir/sectors"

cat >"$stub/findmnt" <<'SH'
#!/bin/bash
printf '/dev/fakedisk\n'
SH
cat >"$stub/readlink" <<'SH'
#!/bin/bash
if [[ $1 == -f ]]; then
  printf '%s\n' "$2"
  exit 0
fi
exec /usr/bin/readlink "$@"
SH
cat >"$stub/df" <<'SH'
#!/bin/bash
printf 'Avail\n999999\n'
SH
cat >"$stub/lsblk" <<'SH'
#!/bin/bash
printf 'TestDisk\n'
SH
cat >"$stub/chattr" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub/mktemp" <<'SH'
#!/bin/bash
template=$1
n=0
[[ -f $MKTEMP_N ]] && n=$(<"$MKTEMP_N")
n=$((n + 1))
printf '%s\n' "$n" >"$MKTEMP_N"
file=${template//XXXXXX/$(printf '%06d' "$n")}
: >"$file"
printf '%s\n' "$file"
SH
cat >"$stub/dd" <<'SH'
#!/bin/bash
of=""
direct=0
urandom=0
for arg in "$@"; do
  case $arg in
    of=*) of=${arg#of=} ;;
    oflag=direct) direct=1 ;;
    if=/dev/urandom) urandom=1 ;;
  esac
done
if (( urandom )) && [[ -n $of ]]; then
  printf 'chunk' >"$of"
  exit 0
fi
if (( direct )) && [[ -n $of ]]; then
  printf 'staged' >"$of"
  sleep 2
  exit 0
fi
exit 0
SH
cat >"$stub/sleep" <<SH
#!/bin/bash
n=\$(<"$tmpdir/sectors")
n=\$((n + 2048))
printf '%s\n' "\$n" >"$tmpdir/sectors"
printf '0 0 0 0 0 0 %s 0 0 0 0\n' "\$n" >"$stat_file"
exec /bin/sleep "\$@"
SH
chmod +x "$stub"/*

output=$(
  PATH="$stub:/usr/bin:/bin" \
    MKTEMP_N="$tmpdir/mktemp-n" \
    OMARCHY_DISK_STAT="$stat_file" \
    OMARCHY_DISK_CHUNK_DIR="$tmpdir/chunk" \
    OMARCHY_DISK_STAGE_ONLY=1 \
    "$ROOT/bin/omarchy-disk-speedtest" "$tmpdir/target"
)

printf '%s\n' "$output" | grep -Eq '^(disk TestDisk|disk fakedisk)$' ||
  fail "disk speedtest still names the disk before staging" "$output"

mapfile -t stage_lines < <(printf '%s\n' "$output" | grep '^stage ')
(( ${#stage_lines[@]} >= 2 )) ||
  fail "disk speedtest emits more than one stage sample while writes are in flight" "$output"

for line in "${stage_lines[@]}"; do
  [[ $line =~ ^stage[[:space:]]+[0-9.]+$ ]] ||
    fail "disk speedtest stage lines are 'stage <rate>'" "$line"
done

printf '%s\n' "$output" | grep -q '^read ' &&
  fail "stage-only run does not start the read phase" "$output"
printf '%s\n' "$output" | grep -q '^write ' &&
  fail "stage-only run does not start the write phase" "$output"

# Staging subprocesses must have finished with the script (the poll loop
# cancelled), not been left behind as dd workers.
leftover=$(pgrep -f "$stub/dd" || true)
[[ -z $leftover ]] || fail "disk speedtest does not leave staging dd running" "$leftover"

pass "disk speedtest emits ordered stage rates and stops when staging finishes"
