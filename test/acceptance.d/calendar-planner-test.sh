#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

STATE_FILE="$HOME/.local/state/omarchy/calendar.json"
STATE_BACKUP=$(mktemp)
STATE_EXISTED=0

if [[ -f $STATE_FILE ]]; then
  cp "$STATE_FILE" "$STATE_BACKUP"
  STATE_EXISTED=1
fi

restore_state() {
  omarchy-shell shell hide omarchy.clock >/dev/null 2>&1 || true
  if ((STATE_EXISTED)); then
    mkdir -p "$(dirname "$STATE_FILE")"
    cp "$STATE_BACKUP" "$STATE_FILE"
  else
    rm -f "$STATE_FILE"
  fi
  rm -f "$STATE_BACKUP"
}

trap restore_state EXIT

press_tabs() {
  local count="$1"
  for ((i = 0; i < count; i++)); do
    wtype -k Tab
  done
}

press_rights() {
  local count="$1"
  for ((i = 0; i < count; i++)); do
    wtype -k Right
    sleep 0.1
  done
}

open_clock() {
  omarchy-shell shell summon omarchy.clock >/dev/null
  wait_until "clock popup opens" 15 layer_present "omarchy-keyboard-panel"
}

restart_source_shell() {
  # The acceptance run is against the checked-out shell, while the session's
  # normal restart command follows the installed OMARCHY_PATH. Restart only
  # this exact development shell so the host's normal shell is untouched.
  timeout 5 quickshell kill -p "$OMARCHY_PATH/shell" --any-display >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 50; attempt++)); do
    pgrep -f "^quickshell -n -p $OMARCHY_PATH/shell$" >/dev/null || break
    sleep 0.1
  done
  setsid env OMARCHY_PATH="$OMARCHY_PATH" QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
    quickshell -n -p "$OMARCHY_PATH/shell" >/tmp/omarchy-calendar-acceptance-shell.log 2>&1 </dev/null &
  wait_until "source shell responds after restart" 30 omarchy-shell shell ping
}

rm -f "$STATE_FILE"
open_clock
wait_until "calendar view is visible" 15 screen_contains "Calendar"
screenshot "success-calendar-planner-01-calendar"

# The original calendar remains keyboard-driven: navigate once and return to
# today without leaving the existing popup.
press_rights 1
wtype "t"
screenshot "success-calendar-planner-02-calendar-navigation"

# Plan is a view of the existing clock popup, not a second bar widget.
wtype "p"
wait_until "planner inbox opens" 15 screen_contains "Planner inbox"
screenshot "success-calendar-planner-03-planner-inbox"

# Save the timezone first, then reopen Settings to configure availability. The
# two saves make the test exercise the explicit, non-silent first-run flow.
press_tabs 2
wtype -k Return
wait_until "planner settings open" 15 screen_contains "Planner settings"
screenshot "success-calendar-planner-04-settings"
wtype -M ctrl -k a -m ctrl
wtype "Europe/Rome"
wtype -k Return
wait_until "timezone settings return to planner" 15 screen_contains "Planner inbox"

press_tabs 2
wtype -k Return
wait_until "saved timezone settings reopen" 15 screen_contains "Planner settings"
press_tabs 4
wtype -k Return
wait_until "availability editor opens" 15 screen_contains "Weekly availability"
screenshot "success-calendar-planner-05-availability"
wtype "09:00"
wtype -k Tab
wtype "17:00"
wtype -k Return
wait_until "availability returns to settings" 15 screen_contains "Planner settings"
wtype -k Escape
wait_until "configured planner returns to inbox" 15 screen_contains "Planner inbox"

# Put a real manual event on the next Monday so the proposal has a busy block
# inside the configured one-day-per-week availability window. The date picker
# starts on today; arrow keys choose the next Monday without typing an ISO
# timestamp into the editor.
wtype -k Escape
omarchy-shell omarchy.clock openView agenda >/dev/null
wait_until "agenda opens" 15 screen_contains "No events yet."
screenshot "success-calendar-planner-06-agenda-empty"
# PlannerView focuses the first action in each view, so Return activates the
# already-focused Add calendar event action.
wtype -k Return
wait_until "event editor opens" 15 screen_contains "Add calendar event"
busy_start=$(date -d 'next monday 11:00' --iso-8601=seconds)
busy_end=$(date -d 'next monday 12:00' --iso-8601=seconds)
days_to_next_monday=$(( (8 - $(date +%u)) % 7 ))
((days_to_next_monday == 0)) && days_to_next_monday=7
wtype "Busy block"
wtype -k Tab
wtype -k Return
sleep 0.5
press_rights "$days_to_next_monday"
wtype -k Return
wtype -k Tab
wtype -M ctrl -k a -m ctrl
wtype "11:00"
wtype -k Tab
wtype -k Return
sleep 0.5
press_rights "$days_to_next_monday"
wtype -k Return
wtype -k Tab
wtype -M ctrl -k a -m ctrl
wtype "12:00"
wtype -k Return
wait_until "manual event appears in agenda" 15 screen_contains "Busy block"
wait_until "manual event is persisted" 15 jq -e --arg title "Busy block" 'any(.events[]; .title == $title and .origin == "manual")' "$STATE_FILE"
screenshot "success-calendar-planner-07-manual-event"

# Add two tasks through the native editor, then edit the second task to depend
# on the first through the native MultiSelect control.
wtype -k Escape
wtype "p"
wait_until "planner reopens after event creation" 15 screen_contains "Planner inbox"

wtype -k Return
wait_until "first task editor opens" 15 screen_contains "Add planning task"
wtype "Prepare acceptance task"
wtype -k Return
wait_until "first task enters the inbox" 15 screen_contains "Prepare acceptance task"

wtype -k Return
wait_until "second task editor opens" 15 screen_contains "Add planning task"
wtype "Follow-up acceptance task"
wtype -k Return
wait_until "second task enters the inbox" 15 screen_contains "Follow-up acceptance task"

first_task=$(jq -r '.tasks[] | select(.title == "Prepare acceptance task") | .id' "$STATE_FILE")
second_task=$(jq -r '.tasks[] | select(.title == "Follow-up acceptance task") | .id' "$STATE_FILE")
[[ -n $first_task && -n $second_task ]] || fail "acceptance tasks are persisted"

# Add task, Settings, first Edit, second Edit.
press_tabs 4
wtype -k Return
wait_until "second task editor reopens" 15 screen_contains "Edit planning task"
sleep 1
press_tabs 7
wtype -k Return
# Let the searchable popup finish its window-focus handoff before typing into
# its search field. This is also the small delay a user naturally provides
# while reading the open dropdown.
sleep 1
wtype "Prepare acceptance task"
wtype -k Down
wtype -k Return
wtype -k Escape
press_tabs 1
wtype -k Return
wait_until "dependency is persisted" 15 jq -e --arg from "$first_task" --arg to "$second_task" 'any(.dependencies[]; .fromTaskId == $from and .toTaskId == $to)' "$STATE_FILE"
screenshot "success-calendar-planner-08-dependent-tasks"

# Ask Omarchy to plan explicitly after the final input change. It must avoid
# the manual event and leave the calendar untouched until Apply schedule.
press_tabs 1
wtype -k Return
wait_until "explicit suggested schedule is ready" 30 jq -e '.proposal.status == "ready" and (.proposal.baseInputRevision == .inputRevision)' "$STATE_FILE"
wait_until "suggested schedule appears in planner" 15 screen_contains "Suggested schedule"
screenshot "success-calendar-planner-09-proposal"

busy_start_epoch=$(date -d "$busy_start" +%s)
busy_end_epoch=$(date -d "$busy_end" +%s)
while IFS=$'\t' read -r start_at end_at; do
  start_epoch=$(date -d "$start_at" +%s)
  end_epoch=$(date -d "$end_at" +%s)
  ((end_epoch <= busy_start_epoch || start_epoch >= busy_end_epoch)) ||
    fail "proposal avoids the manual busy event" "$start_at — $end_at overlaps $busy_start — $busy_end"
done < <(jq -r '.proposal.items[] | select(.scheduled) | [.startAt, .endAt] | @tsv' "$STATE_FILE")
pass "proposal avoids the manual busy event"

jq -e '[.events[] | select(.origin == "planner")] | length == 0' "$STATE_FILE" >/dev/null ||
  fail "calendar remains unchanged before Apply schedule"
pass "calendar remains unchanged before Apply schedule"

# Review and explicitly apply. ProposalReview focuses its apply action when it
# opens, so this is the same keyboard path a user can use without a pointer.
# Plan tasks remains focused after the explicit request. Settings, the
# tutorial dismiss action, the two task actions, and then Review schedule
# follow it in the keyboard order.
press_tabs 5
wtype -k Return
wait_until "proposal review opens" 15 screen_contains "Apply schedule"
screenshot "success-calendar-planner-10-proposal-review"
wtype -k Return
wait_until "proposal is explicitly applied" 15 jq -e '.proposal.status == "applied" and ([.events[] | select(.origin == "planner")] | length) > 0' "$STATE_FILE"
screenshot "success-calendar-planner-11-applied-proposal"

# Restart the checked-out shell, reopen the clock, and prove that applied
# events are state-file data rather than process-local UI state.
wtype -k Escape
restart_source_shell
open_clock
omarchy-shell omarchy.clock openView agenda >/dev/null
wait_until "agenda survives shell restart" 15 screen_contains "Agenda"
wait_until "applied event survives shell restart" 15 jq -e 'any(.events[]; .origin == "planner" and .taskId != null)' "$STATE_FILE"
screenshot "success-calendar-planner-12-restarted-agenda"

# Return the applied planner event to the inbox from the agenda. The planner
# event is ordered before the later manual busy block, so the first event
# action is the explicit Return to inbox.
press_tabs 1
wtype -k Return
wait_until "applied task returns to inbox" 15 jq -e --arg id "$first_task" 'any(.tasks[]; .id == $id and .state == "inbox")' "$STATE_FILE"
wait_until "return to inbox removes only the linked planner event" 15 jq -e --arg id "$first_task" 'all(.events[]; .origin != "planner" or .taskId != $id)' "$STATE_FILE"
pass "return to inbox removes only the linked planner event"
