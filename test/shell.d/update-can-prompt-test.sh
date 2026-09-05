#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
require_command script

helper="$ROOT/bin/omarchy-update-can-prompt"

set +e
"$helper" >/dev/null 2>&1
empty_status=$?
set -e
(( empty_status == 2 )) || fail "a missing descriptor list authorizes prompts"
pass "prompt eligibility fails closed without descriptor arguments"

if "$helper" 0 1 </dev/null >/dev/null; then
  fail "a direct non-terminal caller is allowed to prompt"
fi
pass "direct callers fall back to their live prompt streams"

script -qefc "$helper 0 1" /dev/null >/dev/null </dev/null ||
  fail "a direct pseudo-terminal caller cannot prompt"
pass "direct terminal callers may prompt"

if OMARCHY_UPDATE_UNATTENDED=1 script -qefc "$helper 0 1" /dev/null >/dev/null </dev/null; then
  fail "unattended mode is overridden by a pseudo-terminal"
fi
pass "unattended mode takes precedence over terminal state"

if OMARCHY_UPDATE_LOGGED=1 OMARCHY_UPDATE_CALLER_TTY0=0 OMARCHY_UPDATE_CALLER_TTY1=0 \
  script -qefc "$helper 0 1" /dev/null >/dev/null </dev/null; then
  fail "the update logger's pseudo-terminal overrides the original caller"
fi
pass "captured non-terminal streams remain authoritative after logging"

OMARCHY_UPDATE_LOGGED=1 script -qefc "$helper 0 1" /dev/null >/dev/null </dev/null ||
  fail "a self-update through the legacy logger loses its live terminal"
pass "legacy logged updates fall back to their live terminal until caller state is available"

OMARCHY_UPDATE_LOGGED=1 OMARCHY_UPDATE_CALLER_TTY0=1 OMARCHY_UPDATE_CALLER_TTY1=1 \
  "$helper" 0 1 </dev/null >/dev/null || fail "captured terminal streams are discarded after logging"
pass "captured terminal streams survive the logger wrapper"

set +e
"$helper" 9 >/dev/null 2>&1
invalid_status=$?
set -e
(( invalid_status == 2 )) || fail "an invalid prompt descriptor is not rejected as usage error"
pass "invalid prompt descriptors are rejected"
