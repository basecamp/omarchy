#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command script

fns="$ROOT/default/bash/fns/ssh-reconnect"

# The behavior tests patch the 30-second drop threshold down to 2 seconds so
# they run quickly; make sure the marker they patch still exists.
grep -q 'SECONDS - started < 30' "$fns" ||
  fail "drop threshold marker exists for test patching"
pass "drop threshold marker exists for test patching"

# --- _ssh_interactive parsing ---

run_interactive() {
  bash -c "source '$fns'; _ssh_interactive \"\$@\"" _ "$@"
}

run_interactive -F /dev/null host || fail "plain destination is interactive"
pass "plain destination is interactive"

run_interactive -F /dev/null -p 2222 user@host || fail "separated option value is skipped"
pass "separated option value is skipped"

run_interactive -F /dev/null -4p2222 host || fail "glued option value is skipped"
pass "glued option value is skipped"

run_interactive -F /dev/null -L 8080:localhost:80 -o "ServerAliveInterval=5" host ||
  fail "forwarding and -o options are skipped"
pass "forwarding and -o options are skipped"

if run_interactive -F /dev/null -o "RemoteCommand=uptime" host; then
  fail "configured RemoteCommand is not interactive"
fi
pass "configured RemoteCommand is not interactive"

run_interactive -F /dev/null -o "RemoteCommand=none" host ||
  fail "explicit RemoteCommand none stays interactive"
pass "explicit RemoteCommand none stays interactive"

if run_interactive host uptime; then
  fail "remote command is not interactive"
fi
pass "remote command is not interactive"

if run_interactive -- host uptime; then
  fail "remote command after -- is not interactive"
fi
pass "remote command after -- is not interactive"

if run_interactive -p 2222; then
  fail "missing destination is not interactive"
fi
pass "missing destination is not interactive"

# --- reconnect behavior, run on a pty with a fake ssh ---

fake_dir=$(mktemp -d)
trap 'rm -rf "$fake_dir"' EXIT

cat >"$fake_dir/ssh" <<EOF
#!/bin/bash
[[ \$1 == "-G" ]] && { echo "remotecommand none"; exit 0; }
n=\$(( \$(cat "$fake_dir/count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"$fake_dir/count"
read -r duration code <<<"\$(sed -n "\${n}p" "$fake_dir/plan")"
sleep "\$duration"
exit "\$code"
EOF
chmod +x "$fake_dir/ssh"

cat >"$fake_dir/driver" <<EOF
PATH="$fake_dir:\$PATH"
source <(sed 's/< 30/< 2/' "$fns")
sleep() { :; }
ssh "\$@"
echo "rc=\$?"
EOF

# Each plan line is "<duration> <exit code>" for one fake ssh attempt.
run_case() {
  local plan="$1"
  shift
  printf '%s\n' "$plan" >"$fake_dir/plan"
  rm -f "$fake_dir/count"
  script -qec "bash '$fake_dir/driver' $*" /dev/null | tr -d '\r'
}

attempts() {
  cat "$fake_dir/count"
}

disarm=$(printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h')

out=$(run_case "0 255" host)
[[ $out == *"$disarm"* ]] || fail "stray terminal modes are reset after ssh exits" "$out"
pass "stray terminal modes are reset after ssh exits"

[[ $out == *"rc=255"* ]] && (( $(attempts) == 1 )) ||
  fail "fast connection failure does not reconnect" "$out"
pass "fast connection failure does not reconnect"

out=$(run_case $'2 255\n0 0' host)
[[ $out == *"Connection lost"* ]] && [[ $out == *"rc=0"* ]] && (( $(attempts) == 2 )) ||
  fail "dropped session reconnects" "$out"
pass "dropped session reconnects"

out=$(run_case $'2 255\n0 255\n0 0' host)
[[ $out == *"rc=0"* ]] && (( $(attempts) == 3 )) ||
  fail "reconnecting keeps retrying while the server is still down" "$out"
pass "reconnecting keeps retrying while the server is still down"

out=$(run_case $'2 255\n0 0' host uptime)
[[ $out == *"rc=255"* ]] && (( $(attempts) == 1 )) ||
  fail "remote command exiting 255 is not replayed" "$out"
pass "remote command exiting 255 is not replayed"

printf '%s\n' $'2 255\n0 0' >"$fake_dir/plan"
rm -f "$fake_dir/count"
out=$(script -qec "bash '$fake_dir/driver' host </dev/null" /dev/null | tr -d '\r')
[[ $out == *"rc=255"* ]] && (( $(attempts) == 1 )) ||
  fail "redirected stdin does not reconnect" "$out"
pass "redirected stdin does not reconnect"

# Ctrl-C must stop the loop, not just the in-flight attempt. Only a real
# interactive shell reproduces the job-control process groups this depends on,
# so type the command, the ^C, and the status check into one over a pty. With
# the loop killed, attempts stay low; a surviving loop would drain the whole
# plan before reporting a different status.
cat >"$fake_dir/rcfile" <<EOF
PATH="$fake_dir:\$PATH"
source <(sed 's/< 30/< 2/' "$fns")
sleep() { :; }
PS1='$ '
EOF

plan="2 255"
for _ in {1..12}; do plan+=$'\n1 255'; done
printf '%s\n' "$plan" >"$fake_dir/plan"
rm -f "$fake_dir/count"
out=$({
  printf 'ssh host\n'
  command sleep 4
  printf '\003'
  command sleep 1
  printf 'echo DONE rc=$?\n'
  command sleep 1
  printf 'exit\n'
} | script -qec "bash --rcfile '$fake_dir/rcfile' -i" /dev/null | tr -d '\r')
[[ $out == *"Connection lost"* ]] && [[ $out == *"DONE rc=130"* ]] && (( $(attempts) < 10 )) ||
  fail "Ctrl-C during a retry attempt stops the reconnect loop" "$out"
pass "Ctrl-C during a retry attempt stops the reconnect loop"
