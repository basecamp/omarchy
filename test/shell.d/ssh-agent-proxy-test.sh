#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command socat
require_command ssh-agent
require_command ssh-add
require_command ssh-keygen

WORKDIR=$(mktemp -d)
PIDS=()
cleanup() {
  ((${#PIDS[@]})) && kill "${PIDS[@]}" 2>/dev/null
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Fake home and runtime directory: forwarded agents land under ~/.ssh/agent,
# the local fallback is 1Password's socket, and the relay listens where the
# unit would put it.
export HOME="$WORKDIR/home"
export XDG_RUNTIME_DIR="$WORKDIR/run"
mkdir -p "$HOME/.ssh/agent" "$HOME/.1password" "$XDG_RUNTIME_DIR"

proxy="$XDG_RUNTIME_DIR/omarchy-ssh-agent.sock"

# A real ssh-agent on the given socket, holding one key whose comment names it,
# so listing through the relay says which agent answered.
start_agent() {
  local socket="$1" name="$2" output

  output=$(ssh-agent -a "$socket") || fail "ssh-agent starts on $socket"
  PIDS+=("$(sed -n 's/^SSH_AGENT_PID=\([0-9]*\);.*/\1/p' <<<"$output")")
  ssh-keygen -q -t ed25519 -N '' -C "$name" -f "$WORKDIR/$name"
  SSH_AUTH_SOCK=$socket ssh-add -q "$WORKDIR/$name" 2>/dev/null
}

# A socket file nothing listens on, the way a crashed sshd leaves one behind.
dead_socket() {
  socat UNIX-LISTEN:"$1" - </dev/null >/dev/null 2>&1 &
  local pid=$!
  for _ in {1..50}; do
    [[ -S $1 ]] && break
    sleep 0.1
  done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
}

listed_through_proxy() {
  SSH_AUTH_SOCK=$proxy timeout 20 ssh-add -l 2>&1 || true
}

start_agent "$HOME/.ssh/agent/s.a.sshd.older" older
start_agent "$HOME/.ssh/agent/s.b.sshd.newer" newer
start_agent "$HOME/.1password/agent.sock" local
touch -d '-2 minutes' "$HOME/.ssh/agent/s.a.sshd.older"

socat UNIX-LISTEN:"$proxy",fork,mode=600 EXEC:"$ROOT/bin/omarchy-ssh-agent-proxy" 2>/dev/null &
PIDS+=($!)
for _ in {1..50}; do
  [[ -S $proxy ]] && break
  sleep 0.1
done
[[ -S $proxy ]] || fail "relay socket comes up"

output=$(listed_through_proxy)
[[ $output == *" newer "* && $output != *" older "* ]] ||
  fail "relay picks the newest forwarded agent" "$output"
pass "relay picks the newest forwarded agent"

dead_socket "$HOME/.ssh/agent/s.c.sshd.dead"
output=$(listed_through_proxy)
[[ $output == *" newer "* ]] || fail "relay skips a forwarded socket nobody answers" "$output"
pass "relay skips a forwarded socket nobody answers"

rm "$HOME/.ssh/agent/s.a.sshd.older" "$HOME/.ssh/agent/s.b.sshd.newer" "$HOME/.ssh/agent/s.c.sshd.dead"
output=$(listed_through_proxy)
[[ $output == *" local "* ]] || fail "relay falls back to a local agent" "$output"
pass "relay falls back to a local agent"

rm "$HOME/.1password/agent.sock"
output=$(listed_through_proxy)
[[ $output != *" local "* && $output != *" newer "* ]] ||
  fail "relay answers with an error when no agent is reachable" "$output"
pass "relay answers with an error when no agent is reachable"

# The shell hook: a stale or missing SSH_AUTH_SOCK moves to the relay, a live
# one is left alone.
envs_result() {
  env -i HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" PATH="$PATH" SSH_AUTH_SOCK="$1" \
    bash -c "source '$ROOT/default/bash/envs'; printf '%s' \"\$SSH_AUTH_SOCK\""
}

[[ $(envs_result "$WORKDIR/gone") == "$proxy" ]] || fail "envs points a stale SSH_AUTH_SOCK at the relay"
pass "envs points a stale SSH_AUTH_SOCK at the relay"

[[ $(envs_result "") == "$proxy" ]] || fail "envs points a missing SSH_AUTH_SOCK at the relay"
pass "envs points a missing SSH_AUTH_SOCK at the relay"

start_agent "$HOME/.ssh/agent/s.d.sshd.live" live
[[ $(envs_result "$HOME/.ssh/agent/s.d.sshd.live") == "$HOME/.ssh/agent/s.d.sshd.live" ]] ||
  fail "envs leaves a live SSH_AUTH_SOCK alone"
pass "envs leaves a live SSH_AUTH_SOCK alone"
