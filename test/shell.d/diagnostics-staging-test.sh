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


# --- omarchy-update transcript -------------------------------------------------

# The transcript is read back by omarchy-update-analyze-logs after the run, so
# it keeps a stable name. That name moves off /tmp into the user's own state
# directory, where no other local account can read it and two users running
# the update do not collide on one file.
script_log="$tmpdir/script.log"
: >"$script_log"

cat >"$stub_bin/script" <<SH
#!/bin/bash

printf '%s\n' "\$@" >>"$script_log"
exit 0
SH
chmod +x "$stub_bin/script"

state_home="$tmpdir/xdg-state"
XDG_STATE_HOME="$state_home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update" >/dev/null 2>&1

grep -qF "$state_home/omarchy/update.log" "$script_log" ||
  fail "omarchy update writes its transcript under XDG_STATE_HOME" \
    "script got: $(cat "$script_log")"
pass "omarchy update writes its transcript under XDG_STATE_HOME"

fake_home="$tmpdir/home"
mkdir -p "$fake_home"
: >"$script_log"
env -u XDG_STATE_HOME HOME="$fake_home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update" >/dev/null 2>&1

grep -qF "$fake_home/.local/state/omarchy/update.log" "$script_log" ||
  fail "omarchy update falls back to ~/.local/state without XDG_STATE_HOME" \
    "script got: $(cat "$script_log")"
pass "omarchy update falls back to ~/.local/state without XDG_STATE_HOME"

# --- omarchy-update-analyze-logs -----------------------------------------------

mkdir -p "$state_home/omarchy"
printf 'Updating linux initcpios\n' >"$state_home/omarchy/update.log"
output=$(XDG_STATE_HOME="$state_home" "$ROOT/bin/omarchy-update-analyze-logs" 2>&1)

grep -q "Initramfs generation may have failed" <<<"$output" ||
  fail "omarchy-update-analyze-logs reads the transcript from the state directory" \
    "output: $output"
pass "omarchy-update-analyze-logs reads the transcript from the state directory"

printf 'Updating linux initcpios\nInitcpio image generation successful\n' >"$state_home/omarchy/update.log"
output=$(XDG_STATE_HOME="$state_home" "$ROOT/bin/omarchy-update-analyze-logs" 2>&1)

[[ -z $output ]] ||
  fail "omarchy-update-analyze-logs stays quiet on a good transcript" "output: $output"
pass "omarchy-update-analyze-logs stays quiet on a good transcript"

for update_script in omarchy-update omarchy-update-analyze-logs; do
  grep -q '/tmp/omarchy-update\.log' "$ROOT/bin/$update_script" &&
    fail "$update_script no longer references the fixed /tmp transcript path"
done
pass "update scripts no longer reference the fixed /tmp transcript path"

# --- omarchy-install-gaming-battlenet ------------------------------------------

# The installer log is written by a detached process after the script exits, so
# it cannot be trapped away. It moves from a fixed /tmp name to a fixed name in
# the user's own cache directory, which is private to the user already.
setsid_log="$tmpdir/setsid.log"
: >"$setsid_log"

for tool in omarchy-pkg-add omarchy-install-gaming-gpu-lib32 update-desktop-database; do
  cat >"$stub_bin/$tool" <<'SH'
#!/bin/bash

exit 0
SH
  chmod +x "$stub_bin/$tool"
done

cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

out=""
while (($#)); do
  if [[ $1 == "--output" ]]; then
    shift
    out="$1"
  fi
  shift
done
[[ -z $out ]] || printf 'fake installer\n' >"$out"
exit 0
SH
chmod +x "$stub_bin/curl"

cat >"$stub_bin/setsid" <<SH
#!/bin/bash

printf '%s\n' "\$*" >>"$setsid_log"
exit 0
SH
chmod +x "$stub_bin/setsid"

battle_home="$tmpdir/battle-home"
mkdir -p "$battle_home"

HOME="$battle_home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-install-gaming-battlenet" >/dev/null 2>&1

grep -qF '/tmp/omarchy-battlenet-installer.log' "$setsid_log" &&
  fail "Battle.net installer log moved off the fixed /tmp name" \
    "setsid got: $(cat "$setsid_log")"

grep -qF "$battle_home/.cache/omarchy/battlenet-installer.log" "$setsid_log" ||
  fail "Battle.net installer log stages in the user's cache directory" \
    "setsid got: $(cat "$setsid_log")"
pass "Battle.net installer log stages in the user's cache directory"

# The stub saw the whole command as one line. Pull the path out of the
# redirect target and check the directory the detached writer points at exists,
# since the writer creates the file itself after the script exits.
log_file=$(sed -n "s/.*>'\([^']*\)'.*/\1/p" "$setsid_log" | head -1)
[[ $log_file == "$battle_home/.cache/omarchy/battlenet-installer.log" && -d $(dirname "$log_file") ]] ||
  fail "Battle.net installer log points into the user's cache directory" \
    "setsid got: $(cat "$setsid_log")"
pass "Battle.net installer log points into the user's cache directory"

grep -q '/tmp/omarchy-battlenet-installer\.log' "$ROOT/bin/omarchy-install-gaming-battlenet" &&
  fail "Battle.net installer script no longer names the fixed /tmp log"
pass "Battle.net installer script no longer names the fixed /tmp log"
