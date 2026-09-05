#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The clamshell command against its invariant (docs/clamshell.md):
#   I1  it authors one thing, the clamshell overlay, and never a monitor value
#   I2  a run whose desired overlay state is already on disk changes nothing
#   I3  one reload per transition, exact rollback on failure, retry next run
#   I4  every invocation is serialized, nothing is dropped, nothing can hang
# T1 reads the command's text; T2 shows the config cannot matter; T3 walks the
# transition relation with every collaborator stubbed and controllable.

command_path="$ROOT/bin/omarchy-hyprland-monitor-clamshell"

test_tmp=$(mktemp -d)
trap 'chmod -R u+w "$test_tmp" 2>/dev/null; rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
run_dir="$test_tmp/run"
ctl="$test_tmp/ctl"
log="$test_tmp/calls.log"
toggles="$home_dir/.local/state/omarchy/toggles/hypr"
overlay_file="$toggles/internal-monitor-clamshell.lua"
manual_flag="$toggles/internal-monitor-disable.lua"
mirror_flag="$toggles/internal-monitor-mirror.lua"
monitor_lua="$home_dir/.config/hypr/monitors.lua"
lock="$run_dir/omarchy-monitor-clamshell.lock"
bound=1

mkdir -p "$stub_bin" "$toggles" "$home_dir/.config/hypr" "$run_dir" "$ctl"

# Every collaborator is a stub that logs what it was asked and answers as the
# control directory says: a file named hang-<stub> makes it sleep past the
# command's bound; stubborn-<stub> makes it ignore TERM while doing so, which
# only a KILL escalation bounds; fail-<stub> makes it exit 1; odd-<stub> exit 3.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$OMARCHY_TEST_LOG"
case $1 in
  monitors)
    [[ -e $OMARCHY_TEST_CTL/hang-monitors ]] && sleep 5
    cat "$OMARCHY_TEST_CTL/monitors.json"
    # A valid answer followed by a failure: the reader must treat the query as
    # unknown, never as the printed value.
    [[ -e $OMARCHY_TEST_CTL/slow-monitors ]] && sleep 5
    [[ -e $OMARCHY_TEST_CTL/sour-monitors ]] && exit 1
    exit 0
    ;;
  reload)
    [[ -e $OMARCHY_TEST_CTL/hang-reload ]] && sleep 5
    [[ -e $OMARCHY_TEST_CTL/fail-reload ]] && exit 1
    # What the config would answer once re-read: repair-flips models a config
    # that re-enables the panel; repair-slows and repair-sours make the answer
    # after the reload arrive and then hang, or arrive and then fail.
    [[ -e $OMARCHY_TEST_CTL/repair-flips ]] && printf '[{"name":"eDP-1","description":"Test Panel","disabled":false,"scale":1.25}]' >"$OMARCHY_TEST_CTL/monitors.json"
    [[ -e $OMARCHY_TEST_CTL/repair-slows ]] && touch "$OMARCHY_TEST_CTL/slow-monitors"
    [[ -e $OMARCHY_TEST_CTL/repair-sours ]] && touch "$OMARCHY_TEST_CTL/sour-monitors"
    exit 0 ;;
  dispatch) [[ -e $OMARCHY_TEST_CTL/hang-dispatch ]] && sleep 5; exit 0 ;;
  *) printf 'hyprctl UNEXPECTED %s\n' "$*" >>"$OMARCHY_TEST_LOG"; exit 1 ;;
esac
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
printf 'laptop\n' >>"$OMARCHY_TEST_LOG"
[[ -e $OMARCHY_TEST_CTL/hang-laptop ]] && sleep 5
[[ -e $OMARCHY_TEST_CTL/stubborn-laptop ]] && { trap '' TERM; sleep 5 >/dev/null 2>&1; }
cat "$OMARCHY_TEST_CTL/internal"
SH

# The command's own flock, interposable: fail-flock refuses acquisition, so the
# refusal path can be walked; otherwise the real flock runs.
cat >"$stub_bin/flock" <<SH
#!/bin/bash
[[ -e \$OMARCHY_TEST_CTL/fail-flock ]] && exit 1
exec $(command -v flock) "\$@"
SH

for predicate in omarchy-hw-clamshell omarchy-hyprland-monitor-external-active; do
  short=${predicate##*-}
  cat >"$stub_bin/$predicate" <<SH
#!/bin/bash
printf '$short\n' >>"\$OMARCHY_TEST_LOG"
[[ -e \$OMARCHY_TEST_CTL/hang-$short ]] && sleep 5
[[ -e \$OMARCHY_TEST_CTL/odd-$short ]] && exit 3
exit "\$(cat "\$OMARCHY_TEST_CTL/$short")"
SH
done

# The hosted helpers, stubbed to record their invocation and, when told the
# toggle is stale, to do what the real one does: drop the flag, reload, wake.
for helper in internal internal-mirror; do
  cat >"$stub_bin/omarchy-hyprland-monitor-$helper" <<SH
#!/bin/bash
printf 'helper $helper %s\n' "\$*" >>"\$OMARCHY_TEST_LOG"
[[ -e \$OMARCHY_TEST_CTL/hang-helper-$helper ]] && sleep 5
[[ -e \$OMARCHY_TEST_CTL/stubborn-helper-$helper ]] && { trap '' TERM; sleep 5 >/dev/null 2>&1; }
[[ -e \$OMARCHY_TEST_CTL/escapee-helper-$helper ]] && { (trap '' TERM; exec sleep 5) >/dev/null 2>&1 & exec sleep 5; }
[[ -e \$OMARCHY_TEST_CTL/fail-helper-$helper ]] && exit 1
if [[ -e \$OMARCHY_TEST_CTL/stale-helper-$helper ]]; then
  rm -f "\$OMARCHY_TEST_FLAG_$(tr '-' '_' <<<"$helper")"
  hyprctl reload >/dev/null
  hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null
fi
exit 0
SH
done

chmod +x "$stub_bin"/*

expected_overlay='hl.monitor({ output = "eDP-1", disabled = true })'
stale_overlay='hl.monitor({ output = "OLD-1", disabled = true })'

# The default state is a known panel, lid open, an external active, no toggles
# and no overlay: a run with nothing to do. Cases adjust it with prep strings.
reset_state() {
  chmod -R u+w "$toggles" 2>/dev/null || true
  rm -rf "$ctl" "$toggles"
  mkdir -p "$ctl" "$toggles"
  : >"$log"
  printf 'eDP-1\n' >"$ctl/internal"
  printf '1\n' >"$ctl/clamshell"
  printf '1\n' >"$ctl/active"
  printf '[{"name":"eDP-1","description":"Test Panel","disabled":false,"scale":1.25}]' >"$ctl/monitors.json"
  rm -f "$monitor_lua"
  printf 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.25 })\n' >"$monitor_lua"
}

clamshell() { printf 0 >"$ctl/clamshell"; printf 0 >"$ctl/active"; }
no_name() { : >"$ctl/internal"; }
stale() { printf '%s' "$stale_overlay" >"$overlay_file"; }

run_command() {
  local status=0
  HOME="$home_dir" \
    PATH="$stub_bin:$PATH" \
    XDG_RUNTIME_DIR="$run_dir" \
    OMARCHY_TEST_LOG="$log" \
    OMARCHY_TEST_CTL="$ctl" \
    OMARCHY_TEST_FLAG_internal="$manual_flag" \
    OMARCHY_TEST_FLAG_internal_mirror="$mirror_flag" \
    OMARCHY_HYPRCTL_TIMEOUT="$bound" \
    "$command_path" >/dev/null 2>&1 || status=$?
  return $status
}

count_calls() { grep -c "^$1" "$log" || true; }
reloads() { count_calls 'hyprctl reload'; }
dispatches() { count_calls 'hyprctl dispatch'; }
evals() { count_calls 'hyprctl eval'; }
helper_calls() { count_calls 'helper'; }

overlay_equals() {
  [[ -f $overlay_file ]] && [[ $(< "$overlay_file") == "$1" ]]
}

listing() { ls -liA --time-style=full-iso "$toggles"; }

# ---------------------------------------------------------------- T1: the text

! grep -qE 'hyprctl[[:space:]]+(eval|keyword)' "$command_path" || fail "T1: the command does not write monitor values with hyprctl eval or keyword"
! grep -qE '(^|[^A-Za-z0-9_./-])(awk|gawk|lua|lua5\.[0-9])([^A-Za-z0-9_.-]|$)' "$command_path" || fail "T1: the command invokes no reader (awk or lua)"
! grep -q 'monitors\.lua' "$command_path" || fail "T1: the command does not name the config file"
verbs=$(grep -oE 'hyprctl[[:space:]]+[a-z]+' "$command_path" | awk '{print $2}' | sort -u | tr '\n' ' ')
for verb in $verbs; do
  case $verb in monitors|reload|dispatch) ;; *) fail "T1: hyprctl verb $verb is not one of monitors, reload, dispatch" ;; esac
done
grep -q 'flock' "$command_path" || fail "T1: the command serializes itself with a lock"
pass "T1: the command's text authors nothing but the overlay and reads no config"

# ------------------------------- P1: the external-active predicate's contract

# The tri-state reading is only as honest as the predicates' exits: 0 true,
# 1 known false, anything else only for a genuine unknown. The real predicate
# is run against a controlled hyprctl: the query succeeding with no active
# external is the contracted false, the query failing is never taken for it,
# and Hyprland's reserved FALLBACK placeholder is never a monitor.
p1_ctl="$test_tmp/p1-ctl"; p1_bin="$test_tmp/p1-bin"
mkdir -p "$p1_ctl" "$p1_bin"
cat >"$p1_bin/hyprctl" <<'SH'
#!/bin/bash
[[ -e $P1_CTL/fail ]] && exit 1
cat "$P1_CTL/out"
SH
chmod +x "$p1_bin/hyprctl"
p1_case() {
  local expect="$1" label="$2" got=0
  P1_CTL="$p1_ctl" PATH="$p1_bin:$PATH" "$ROOT/bin/omarchy-hyprland-monitor-external-active" >/dev/null 2>&1 || got=$?
  (( got == expect )) || fail "P1 ($label): exit $expect" "got $got"
}
printf '[{"name":"eDP-1","disabled":false},{"name":"HDMI-A-1","disabled":false}]' >"$p1_ctl/out"
p1_case 0 "an enabled external is true"
printf '[{"name":"eDP-1","disabled":false}]' >"$p1_ctl/out"
p1_case 1 "only the internal panel is the contracted false"
printf '[{"name":"eDP-1","disabled":false},{"name":"HDMI-A-1","disabled":true}]' >"$p1_ctl/out"
p1_case 1 "a disabled external is the contracted false"
printf '[]' >"$p1_ctl/out"
p1_case 1 "no outputs listed is the contracted false"
printf '[{"name":"eDP-1","disabled":true},{"name":"Virtual-1","disabled":true},{"name":"FALLBACK","disabled":false}]' >"$p1_ctl/out"
p1_case 1 "the FALLBACK placeholder beside disabled outputs is not an external"
printf '[{"name":"eDP-1","disabled":true},{"name":"FALLBACK","disabled":false},{"name":"HDMI-A-1","disabled":false}]' >"$p1_ctl/out"
p1_case 0 "a real enabled external beside FALLBACK is still true"
printf 'not json' >"$p1_ctl/out"
p1_case 2 "an unreadable answer is unknown"
: >"$p1_ctl/out"
p1_case 2 "an empty answer is unknown"
touch "$p1_ctl/fail"
p1_case 2 "a failing query is unknown, never false"
rm -f "$p1_ctl/fail"
pass "P1: the external-active predicate answers 0, 1, or unknown -- and a failure is never false"

# ------------------------------------------------- T2: the config cannot matter

# Both transitions are made under configs that any reader would answer
# differently: the panel at another scale, no file, a file that cannot be read,
# one Lua rejects, and one that answers by whether it runs in a sandbox. The
# calls to Hyprland are the same under every one of them.
t2_calls() {
  reset_state
  [[ $2 == enable ]] && stale || clamshell
  case $1 in
    plain) ;;
    other) printf 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })\n' >"$monitor_lua" ;;
    absent) rm -f "$monitor_lua" ;;
    unreadable) chmod 000 "$monitor_lua" ;;
    rejected) printf 'local x = (\n' >"$monitor_lua" ;;
    adversarial) printf 'local seen = os ~= nil\nhl.monitor({ output = "eDP-1", position = seen and "left" or "0x0", scale = seen and 3 or 1.25 })\n' >"$monitor_lua" ;;
  esac
  run_command || fail "T2: the $2 transition runs with a $1 config"
  grep '^hyprctl' "$log" || true
}
for transition in enable disable; do
  baseline=$(t2_calls plain "$transition")
  for kind in other absent unreadable rejected adversarial; do
    [[ $(t2_calls "$kind" "$transition") == "$baseline" ]] || fail "T2: the $transition transition makes the same calls with a $kind config" "$baseline"
  done
  (( $(reloads) == 1 && $(evals) == 0 )) || fail "T2: the $transition transition is one reload and no written value" "$baseline"
done
pass "T2: the config's content cannot matter, since the command never reads it"

# ---------------------------------------- T3: the transition relation (I2, I3, I4)

# Rows of the relation, from both starting states.
for start in absent stale; do
  prime() {
    reset_state
    [[ $start == stale ]] && stale
    eval "$1"
  }
  untouched_after() {
    if [[ $start == stale ]]; then overlay_equals "$stale_overlay"; else [[ ! -e $overlay_file ]]; fi
  }

  # unsafe name: refuse before any effect
  prime 'printf "eDP-1; rm -rf x\n" >"$ctl/internal"; clamshell; touch "$manual_flag" "$mirror_flag"'
  ! run_command || fail "T3 ($start): an unsafe internal name is refused with exit 1"
  untouched_after || fail "T3 ($start): an unsafe name leaves the overlay untouched"
  (( $(reloads) == 0 && $(dispatches) == 0 && $(evals) == 0 && $(helper_calls) == 0 )) || fail "T3 ($start): an unsafe name causes no effect, and the helpers are not entered"

  # unknown name + clamshell: untouched
  prime 'no_name; clamshell'
  run_command || fail "T3 ($start): unknown name in clamshell runs"
  untouched_after || fail "T3 ($start): unknown name in clamshell leaves the overlay untouched"
  (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 ($start): unknown name in clamshell reloads and dispatches nothing"

  # unknown name, not clamshell: absent, one reload, no wake
  prime 'no_name'
  run_command || fail "T3 ($start): unknown name out of clamshell runs"
  [[ ! -e $overlay_file ]] || fail "T3 ($start): unknown name out of clamshell leaves no overlay"
  if [[ $start == stale ]]; then (( $(reloads) == 1 )) || fail "T3 (stale): removing a stale overlay for no known panel reloads exactly once"; else (( $(reloads) == 0 )) || fail "T3 (absent): nothing to remove, no reload"; fi
  (( $(dispatches) == 0 )) || fail "T3 ($start): no panel to wake without a known name"

  # known + clamshell + manual toggle: untouched
  prime 'clamshell; touch "$manual_flag"'
  run_command || fail "T3 ($start): manual toggle in clamshell runs"
  untouched_after || fail "T3 ($start): the manual toggle leaves the overlay untouched"
  (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 ($start): the manual toggle in clamshell reloads and dispatches nothing"

  # known + clamshell: exact overlay, one reload; again: nothing
  prime 'clamshell'
  run_command || fail "T3 ($start): clamshell runs"
  overlay_equals "$expected_overlay" || fail "T3 ($start): clamshell writes exactly the overlay"
  (( $(reloads) == 1 && $(dispatches) == 0 && $(evals) == 0 )) || fail "T3 ($start): clamshell reloads exactly once and writes no value"
  : >"$log"; run_command || fail "T3 ($start): clamshell again runs"
  (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 ($start): clamshell with the overlay in place does nothing"
  overlay_equals "$expected_overlay" || fail "T3 ($start): the overlay is unchanged by an idempotent run"

  # known, not clamshell: absent, one reload, one wake
  prime ':'
  run_command || fail "T3 ($start): out of clamshell runs"
  [[ ! -e $overlay_file ]] || fail "T3 ($start): out of clamshell leaves no overlay"
  if [[ $start == stale ]]; then
    (( $(reloads) == 1 && $(dispatches) == 1 )) || fail "T3 (stale): leaving clamshell reloads once and wakes once"
    grep -q 'dispatch hl.dsp.dpms({ action = "enable", monitor = "eDP-1" })' "$log" || fail "T3 (stale): the wake names the panel"
  else
    (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 (absent): out of clamshell with no overlay does nothing"
  fi
done
pass "T3: every row of the relation from both starting states"

# The wake guard on the enable path: manual toggle on, external active / not / unknown.
for active in 0 1 hang; do
  reset_state; stale; touch "$manual_flag"
  if [[ $active == hang ]]; then touch "$ctl/hang-active"; printf 1 >"$ctl/active"; else printf "$active" >"$ctl/active"; fi
  run_command || fail "T3: enable with manual toggle and active=$active runs"
  [[ ! -e $overlay_file ]] && (( $(reloads) == 1 )) || fail "T3: enable with manual toggle removes the overlay and reloads once (active=$active)"
  if [[ $active == 1 ]]; then (( $(dispatches) == 1 )) || fail "T3: manual toggle with no external active still wakes"; else (( $(dispatches) == 0 )) || fail "T3: manual toggle with external active or unknown suppresses the wake (active=$active)"; fi
done
pass "T3: the wake guard treats unknown as active"

# The 3x3 predicate matrix, overlay present and stale, name known.
for lid in 0 1 2; do
  for ext in 0 1 2; do
    reset_state; stale
    for pair in "clamshell:$lid" "active:$ext"; do
      p=${pair%%:*}; v=${pair##*:}
      if (( v == 2 )); then touch "$ctl/hang-$p"; printf 1 >"$ctl/$p"; else printf "$v" >"$ctl/$p"; fi
    done
    run_command || fail "T3 matrix ($lid,$ext): runs"
    if (( lid == 1 || ext == 1 )); then
      [[ ! -e $overlay_file ]] && (( $(reloads) == 1 && $(dispatches) == 1 )) || fail "T3 matrix ($lid,$ext): a known false is not clamshell: overlay removed, one reload, one wake"
    elif (( lid == 2 || ext == 2 )); then
      overlay_equals "$stale_overlay" && (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 matrix ($lid,$ext): unknown leaves the overlay untouched"
    else
      overlay_equals "$expected_overlay" && (( $(reloads) == 1 )) || fail "T3 matrix (0,0): clamshell rewrites a stale overlay and reloads once"
    fi
  done
done
pass "T3: the three-valued conjunction: false dominates, unknown suspends, both true is clamshell"

# Rollback is byte-exact, from a file, never synthesized.
for trailing in 0 3; do
  reset_state; clamshell; touch "$ctl/fail-reload"
  { stale; for ((i = 0; i < trailing; i++)); do printf '\n'; done >>"$overlay_file"; }
  cp "$overlay_file" "$test_tmp/prior"
  run_command || fail "T3 rollback ($trailing newlines): runs"
  cmp -s "$overlay_file" "$test_tmp/prior" || fail "T3 rollback ($trailing newlines): a failed reload puts back the exact prior bytes"
  (( $(reloads) == 1 )) || fail "T3 rollback ($trailing newlines): one reload attempt"
  rm -f "$ctl/fail-reload"; : >"$log"
  run_command || fail "T3 rollback ($trailing newlines): the next run runs"
  overlay_equals "$expected_overlay" && (( $(reloads) == 1 )) || fail "T3 rollback ($trailing newlines): the next run retries the transition"
done
reset_state; no_name; stale; touch "$ctl/fail-reload"; cp "$overlay_file" "$test_tmp/prior"
run_command || fail "T3 rollback (unknown name): runs"
cmp -s "$overlay_file" "$test_tmp/prior" || fail "T3 rollback (unknown name): the enable side puts back the exact prior bytes"
! grep -rq 'output = ""' "$toggles" || fail "T3 rollback (unknown name): no overlay for an empty name is ever written"
rm -f "$ctl/fail-reload"; : >"$log"; run_command || true
[[ ! -e $overlay_file ]] && (( $(reloads) == 1 )) || fail "T3 rollback (unknown name): the next run removes the stale overlay"
pass "T3: rollback restores the exact prior bytes and the next run retries"

# No debris, both sides, including a directory that cannot be written.
for side in place remove; do
  reset_state
  if [[ $side == place ]]; then clamshell; else stale; cp "$overlay_file" "$test_tmp/prior"; fi
  chmod 555 "$toggles"
  run_command || fail "T3 read-only ($side): runs"
  if [[ $side == place ]]; then [[ ! -e $overlay_file ]] || fail "T3 read-only (place): no overlay appears"; else cmp -s "$overlay_file" "$test_tmp/prior" || fail "T3 read-only (remove): the overlay stands byte-for-byte"; fi
  (( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 read-only ($side): a transition that cannot be made attempts no reload and no wake"
  chmod 755 "$toggles"
  [[ $(ls -A "$toggles" | grep -v '^internal-monitor-clamshell.lua$' | wc -l) -eq 0 ]] || fail "T3 read-only ($side): no debris"
done
reset_state; clamshell; mkdir "$overlay_file"
run_command || fail "T3 directory: a directory at the overlay's path runs"
[[ -d $overlay_file && -z $(ls -A "$overlay_file") ]] && (( $(reloads) == 0 )) || fail "T3 directory: a directory at the overlay's path is left as it is, with nothing in it, and no reload" "$(ls -lA "$toggles" "$overlay_file")"
[[ $(ls -A "$toggles" | wc -l) -eq 1 ]] || fail "T3 directory: no debris beside it"
pass "T3: a transition that cannot be made is not attempted and leaves nothing"

# A killed run's debris -- the EXIT trap does not run on SIGKILL -- is swept
# under the lock by the next run that passes name validation, before either
# hosted helper can end that run early.
reset_state; clamshell; printf 'orphan' >"$toggles/.internal-monitor-clamshell.tmpXYZ"; printf 'old bytes' >"$toggles/.internal-monitor-clamshell.prior.XYZ123"
run_command || fail "T3 sweep: runs over a killed run's debris"
[[ ! -e $toggles/.internal-monitor-clamshell.tmpXYZ && ! -e $toggles/.internal-monitor-clamshell.prior.XYZ123 ]] || fail "T3 sweep: the debris is gone" "$(ls -A "$toggles")"
overlay_equals "$expected_overlay" && (( $(reloads) == 1 )) || fail "T3 sweep: the run's own transition still happens"
reset_state; printf 'orphan' >"$toggles/.internal-monitor-clamshell.prior.ABC456"
run_command || fail "T3 sweep: an idempotent run still sweeps"
[[ ! -e $toggles/.internal-monitor-clamshell.prior.ABC456 ]] || fail "T3 sweep: debris does not survive a no-op run"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 sweep: sweeping is not a transition"
reset_state; touch "$manual_flag" "$ctl/fail-helper-internal"; printf 'orphan' >"$toggles/.internal-monitor-clamshell.prior.DEF789"
run_command || true
[[ ! -e $toggles/.internal-monitor-clamshell.prior.DEF789 ]] || fail "T3 sweep: a failing helper cannot end the run before the sweep"
pass "T3: a killed run's leftover files are swept by the next run that passes name validation, before either helper can exit early"

# Nothing is created on an idempotent run: the same run with the directory read-only is identical.
idempotent_case() {
  local label="$1"
  reset_state; eval "$2"
  run_command || fail "T3 idempotent ($label): runs"; first=$(grep '^hyprctl' "$log" || true); before=$(listing)
  : >"$log"; chmod 555 "$toggles"
  run_command || fail "T3 idempotent ($label): runs read-only"; second=$(grep '^hyprctl' "$log" || true); after=$(listing)
  chmod 755 "$toggles"
  [[ $first == "$second" && $before == "$after" ]] || fail "T3 idempotent ($label): an idempotent run creates nothing and behaves the same read-only"
}
idempotent_case "clamshell with the exact overlay" 'clamshell; printf "%s\n" "$expected_overlay" >"$overlay_file"'
idempotent_case "manual toggle with a stale overlay" 'clamshell; touch "$manual_flag"; stale'
idempotent_case "unknown name in clamshell" 'no_name; clamshell; stale'
idempotent_case "out of clamshell with no overlay" ':'
pass "T3: idempotent runs create no file, not even transiently"

# The lock: a holder delays but never drops; two at once make one transition.
reset_state; clamshell
( flock 9; sleep 3 ) 9>"$lock" &
holder=$!; sleep 0.3
started=$SECONDS; run_command || fail "T3 lock: a queued run completes"; elapsed=$(( SECONDS - started ))
wait "$holder" 2>/dev/null || true
(( elapsed >= 2 )) || fail "T3 lock: the run waited for the holder" "elapsed ${elapsed}s"
overlay_equals "$expected_overlay" && (( $(reloads) == 1 )) || fail "T3 lock: the queued run made its transition"
reset_state; clamshell
run_command & one=$!; run_command & two=$!; wait "$one" "$two" || true
overlay_equals "$expected_overlay" && (( $(reloads) == 1 )) || fail "T3 lock: two runs at once make one transition and one reload"
pass "T3: the lock queues and never drops, and serializes concurrent runs"

# Every call class bounded: the command finishes, the lock is released, and the state is the conservative one.
hang_case() {
  local what="$1" prep="$2" check="$3"
  reset_state; eval "$prep"; touch "$ctl/hang-$what"
  started=$SECONDS; run_command || true; elapsed=$(( SECONDS - started ))
  (( elapsed <= bound + 2 )) || fail "T3 hang ($what): the command finishes within the bound" "elapsed ${elapsed}s"
  flock -n "$lock" true || fail "T3 hang ($what): the lock is released"
  eval "$check" || fail "T3 hang ($what): the conservative outcome"
}
# A callee that ignores TERM: only the KILL escalation bounds it. The same
# assertions as a hang, held under the harder stub.
stubborn_case() {
  local what="$1" prep="$2" check="$3"
  reset_state; eval "$prep"; touch "$ctl/stubborn-$what"
  started=$SECONDS; run_command || true; elapsed=$(( SECONDS - started ))
  (( elapsed <= bound + 3 )) || fail "T3 stubborn ($what): the command finishes within the bound and the kill grace" "elapsed ${elapsed}s"
  flock -n "$lock" true || fail "T3 stubborn ($what): the lock is released"
  eval "$check" || fail "T3 stubborn ($what): the conservative outcome"
}

still_stale='overlay_equals "$stale_overlay" && (( $(reloads) == 0 ))'
hang_case laptop 'clamshell; stale' "$still_stale"
hang_case clamshell 'printf 0 >"$ctl/active"; stale' "$still_stale"
hang_case clamshell 'printf 1 >"$ctl/active"; stale' '[[ ! -e $overlay_file ]] && (( $(reloads) == 1 ))'
hang_case active 'printf 0 >"$ctl/clamshell"; stale' "$still_stale"
hang_case reload 'clamshell' '[[ ! -e $overlay_file ]] && (( $(reloads) == 1 ))'
hang_case dispatch 'stale' '[[ ! -e $overlay_file ]] && (( $(reloads) == 1 && $(dispatches) == 1 ))'
hang_case helper-internal 'touch "$manual_flag"; stale' "$still_stale"
hang_case helper-internal-mirror 'touch "$mirror_flag"; stale' "$still_stale"
stubborn_case laptop 'clamshell; stale' "$still_stale"
stubborn_case helper-internal 'touch "$manual_flag"; stale' "$still_stale"
pass "T3: every call class is bounded, releases the lock, and fails toward untouched"

# A callee that dies on TERM but leaves a TERM-ignoring descendant behind: the
# descendant must not have the lock descriptor to hold, so the lock is free the
# moment the command exits.
reset_state; touch "$manual_flag" "$ctl/escapee-helper-internal"; stale
started=$SECONDS; run_command || true; elapsed=$(( SECONDS - started ))
(( elapsed <= bound + 3 )) || fail "T3 escapee: the command finishes within the bound" "elapsed ${elapsed}s"
flock -n "$lock" true || fail "T3 escapee: no descendant holds the lock after the command exits"
overlay_equals "$stale_overlay" && (( $(reloads) == 0 )) || fail "T3 escapee: the conservative outcome"
pass "T3: a surviving descendant of a bounded callee cannot hold the lock"

# A lock that cannot be taken is a run that must not happen: exit 1 before any
# lookup, helper or transition.
reset_state; clamshell; touch "$manual_flag" "$ctl/fail-flock"
! run_command || fail "T3 flock: a lock that cannot be taken exits non-zero"
[[ ! -s $log ]] || fail "T3 flock: no collaborator is called unserialized" "$(cat "$log")"
[[ ! -e $overlay_file ]] || fail "T3 flock: no transition is made unserialized"
reset_state; clamshell; rm -f "$lock"; chmod 555 "$run_dir"
! run_command || fail "T3 flock: a lock file that cannot be opened exits non-zero"
chmod 755 "$run_dir"
[[ ! -s $log ]] || fail "T3 flock: no collaborator is called without a lock file" "$(cat "$log")"
pass "T3: a lock that cannot be taken stops the run before any effect"

# The repair: a compositor holding the panel disabled while nothing on disk
# wants it off -- what a helper killed between its flag removal and its reload
# leaves behind -- gets one reload, only while no external monitor is active;
# the wake follows only when the reload actually brought the panel back. A
# config that keeps the panel disabled is reloaded again on a later run -- the
# stated stateless trade -- but never woken; every unknown repairs nothing,
# including a valid answer followed by a hang or a failure, at either query.
panel_held() { printf '[{"name":"eDP-1","description":"Test Panel","disabled":%s,"scale":1.25}]' "$1" >"$ctl/monitors.json"; }
reset_state; panel_held true; touch "$ctl/repair-flips"
run_command || fail "T3 repair: runs"
(( $(reloads) == 1 && $(dispatches) == 1 )) || fail "T3 repair: a stale disabled panel gets one reload and one wake" "$(cat "$log")"
[[ ! -e $overlay_file ]] && [[ $(ls -A "$toggles" | wc -l) -eq 0 ]] || fail "T3 repair: nothing is written"
: >"$log"; run_command || fail "T3 repair: runs once repaired"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 repair: a panel the compositor reports enabled repairs nothing"
reset_state; panel_held true
run_command || fail "T3 repair (config-disabled): runs"
(( $(reloads) == 1 && $(dispatches) == 0 )) || fail "T3 repair: a config that keeps the panel disabled is never woken" "$(cat "$log")"
: >"$log"; run_command || fail "T3 repair (config-disabled): runs again"
(( $(reloads) == 1 && $(dispatches) == 0 )) || fail "T3 repair: the stateless trade reloads again on a later run, and still never wakes" "$(cat "$log")"
reset_state; printf 'not json' >"$ctl/monitors.json"
run_command || fail "T3 repair (unreadable before): runs"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 repair: an unreadable answer before the reload repairs nothing"
reset_state; panel_held true; touch "$ctl/slow-monitors"
run_command || fail "T3 repair (masked hang before): runs"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 repair: a valid answer followed by a hang is an unknown, not a repair" "$(cat "$log")"
reset_state; panel_held true; touch "$ctl/sour-monitors"
run_command || fail "T3 repair (masked failure before): runs"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 repair: a valid answer followed by a failure is an unknown, not a repair"
reset_state; panel_held true; touch "$ctl/repair-flips" "$ctl/repair-slows"
run_command || fail "T3 repair (masked hang after): runs"
(( $(reloads) == 1 && $(dispatches) == 0 )) || fail "T3 repair: a valid answer followed by a hang after the reload wakes nothing" "$(cat "$log")"
reset_state; panel_held true; touch "$ctl/repair-flips" "$ctl/repair-sours"
run_command || fail "T3 repair (masked failure after): runs"
(( $(reloads) == 1 && $(dispatches) == 0 )) || fail "T3 repair: a valid answer followed by a failure after the reload wakes nothing"
reset_state; printf 0 >"$ctl/active"; panel_held true
run_command || fail "T3 repair (external active): runs"
(( $(reloads) == 0 && $(dispatches) == 0 )) || fail "T3 repair: an active external monitor suppresses the repair"
reset_state; touch "$manual_flag"; panel_held true
run_command || fail "T3 repair (manual toggle): runs"
(( $(reloads) == 0 )) && ! grep -q '^hyprctl monitors' "$log" || fail "T3 repair: an intentional disable repairs nothing and asks nothing"
reset_state; no_name; panel_held true
run_command || fail "T3 repair (unknown name): runs"
(( $(reloads) == 0 )) && ! grep -q '^hyprctl monitors' "$log" || fail "T3 repair: no name, no question, no repair"
reset_state; panel_held true; touch "$ctl/hang-monitors"
started=$SECONDS; run_command || true; elapsed=$(( SECONDS - started ))
(( elapsed <= bound + 3 && $(reloads) == 0 )) || fail "T3 repair: an unanswered compositor is an unknown, bounded and repairing nothing" "elapsed ${elapsed}s"
reset_state; panel_held true; touch "$ctl/fail-reload"
run_command || fail "T3 repair (failed reload): runs"
(( $(reloads) == 1 && $(dispatches) == 0 )) || fail "T3 repair: a failed repair reload wakes nothing"
rm -f "$ctl/fail-reload"; touch "$ctl/repair-flips"; : >"$log"; run_command || fail "T3 repair (retry): runs"
(( $(reloads) == 1 && $(dispatches) == 1 )) || fail "T3 repair: the next run retries the repair"
pass "T3: a stale compositor-held disable is repaired exactly when it strands the machine, and no masked query is believed"

# The hosted helpers: not entered without their flags; entered and ordered with them; a failure stops the run.
reset_state; run_command || true
(( $(helper_calls) == 0 )) || fail "T3 helpers: with both toggle flags absent, neither helper is invoked"
reset_state; touch "$manual_flag" "$ctl/stale-helper-internal"; stale
run_command || fail "T3 helpers: the combined case runs"
[[ $(grep -E '^(helper|hyprctl (reload|dispatch))' "$log" | sed 's/ hl\.dsp.*//' | tr '\n' ';') == "helper internal recover;hyprctl reload;hyprctl dispatch;hyprctl reload;hyprctl dispatch;" ]] || fail "T3 helpers: the helper's transition precedes the clamshell transition, two reloads and two wakes" "$(cat "$log")"
[[ ! -e $manual_flag && ! -e $overlay_file ]] || fail "T3 helpers: both the stale toggle and the overlay are gone"
reset_state; touch "$manual_flag" "$ctl/fail-helper-internal"; stale
run_command || true
overlay_equals "$stale_overlay" && (( $(reloads) == 0 )) || fail "T3 helpers: a failing helper stops the run before the clamshell transition"
pass "T3: the hosted helpers are gated by their flags, ordered, and stop the run when they fail"
