#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

source "$ROOT/default/bash/fns/ssh-port-forwarding"

# dip and lip select processes with pkill/pgrep -f, which match a POSIX ERE
# against the whole /proc cmdline. Only a real process carrying a real argv
# exercises that, so every case here is a `sleep` wearing the command line under
# test: matching the pattern against a string with another regex engine would
# pass while dip was broken against the machine (#8917).
decoys=()

spawn_decoy() {
  local argv="$1" attempt

  bash -c 'exec -a "$1" sleep 120' _ "$argv" &
  decoys+=($!)

  for attempt in {1..100}; do
    [[ $(cat "/proc/${decoys[-1]}/comm" 2>/dev/null) == "sleep" ]] && return 0
    sleep 0.1
  done

  fail "decoy reaches the kernel with its argv: $argv" "pid ${decoys[-1]} never exec'd"
}

cleanup() {
  (( ${#decoys[@]} > 0 )) && kill "${decoys[@]}" 2>/dev/null

  return 0
}
trap cleanup EXIT

# A killed decoy stays in the table as a zombie until this shell reaps it, so
# /proc existing is not the same as still running.
running() {
  local state

  state=$(sed -n 's/^State:[[:space:]]*//p' "/proc/$1/status" 2>/dev/null) || return 1
  [[ -n $state && $state != Z* ]]
}

assert_stopped() {
  local description="$1" pid="$2" attempt

  for attempt in {1..50}; do
    running "$pid" || break
    sleep 0.1
  done

  if running "$pid"; then
    fail "$description" "pid $pid is still running"
  else
    pass "$description"
  fi
}

assert_running() {
  local description="$1" pid="$2"

  if running "$pid"; then
    pass "$description"
  else
    fail "$description" "pid $pid was killed"
  fi
}

# Ports nothing else would be forwarding, since dip's pkill sweeps every process
# on the machine running the suite.
fip_port=59317
bare_port=59318
path_port=59319
prefix_port=5931

spawn_decoy "ssh -f -N -L $fip_port:localhost:$fip_port example.invalid"
spawn_decoy "notssh -L $fip_port:localhost:$fip_port example.invalid"
spawn_decoy "ssh -L $bare_port:localhost:$bare_port example.invalid"
spawn_decoy "/usr/bin/ssh -f -N -L $path_port:localhost:$path_port example.invalid"
spawn_decoy "ssh -f -N -L $prefix_port:localhost:$fip_port example.invalid"
fip_decoy=${decoys[0]}
impostor_decoy=${decoys[1]}
bare_decoy=${decoys[2]}
path_decoy=${decoys[3]}
prefix_decoy=${decoys[4]}

listed=$(lip)
for entry in "$fip_decoy:forward fip creates" "$bare_decoy:hand-made forward" "$path_decoy:forward run by absolute path"; do
  if grep -q "^${entry%%:*} " <<<"$listed"; then
    pass "lip lists the ${entry#*:}"
  else
    fail "lip lists the ${entry#*:}" "$listed"
  fi
done

if grep -q "^$impostor_decoy " <<<"$listed"; then
  fail "lip ignores a command line that only mentions the forward" "$listed"
else
  pass "lip ignores a command line that only mentions the forward"
fi

stopped=$(dip "$fip_port")
assert_stopped "dip stops the forward fip creates" "$fip_decoy"
assert_running "dip spares a non-ssh command line carrying the same -L fragment" "$impostor_decoy"
if [[ $stopped == "Stopped forwarding port $fip_port" ]]; then
  pass "dip reports the port it stopped"
else
  fail "dip reports the port it stopped" "$stopped"
fi

dip "$bare_port" >/dev/null
assert_stopped "dip stops a forward with no flags before -L" "$bare_decoy"

dip "$path_port" >/dev/null
assert_stopped "dip stops a forward run by absolute path" "$path_decoy"

# 5931 is a prefix of 59317, so a pattern that does not end at the port kills a
# forward the user never named.
missing=$(dip "$prefix_port")
assert_running "dip spares a forward whose port merely starts with the argument" "$prefix_decoy"
if [[ $missing == "No forwarding on port $prefix_port" ]]; then
  pass "dip reports a port it found nothing on"
else
  fail "dip reports a port it found nothing on" "$missing"
fi
