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

open_clock() {
  omarchy-shell shell summon omarchy.clock >/dev/null
  wait_until "clock popup opens" 15 layer_present "omarchy-keyboard-panel"
}

rm -f "$STATE_FILE"
open_clock
wait_until "calendar view is visible" 15 screen_contains "Calendar"
screenshot "success-calendar-planner-01-calendar"

# The original calendar remains keyboard-driven: navigate once and return to
# today without leaving the existing popup.
wtype -k Right
wtype "t"
screenshot "success-calendar-planner-02-calendar-navigation"

# Plan is a view of the existing clock popup, not a second bar widget.
wtype "p"
wait_until "planner inbox opens" 15 screen_contains "Planner inbox"
screenshot "success-calendar-planner-03-planner-inbox"

# Save the timezone first, then reopen Settings to configure availability. The
# two saves make the test exercise the explicit, non-silent first-run flow.
press_tabs 1
wtype -k Return
wait_until "planner settings open" 15 screen_contains "Planner settings"
screenshot "success-calendar-planner-04-settings"
wtype -M ctrl -k a -m ctrl
wtype "Europe/Rome"
wtype -k Return
wait_until "timezone settings return to planner" 15 screen_contains "Planner inbox"

press_tabs 1
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
# inside the configured one-day-per-week availability window.
wtype -k Escape
wtype "a"
wait_until "agenda opens" 15 screen_contains "Agenda"
screenshot "success-calendar-planner-06-agenda-empty"
press_tabs 1
wtype -k Return
wait_until "event editor opens" 15 screen_contains "Add event"
busy_start=$(date -d 'next monday 11:00' --iso-8601=seconds)
busy_end=$(date -d 'next monday 12:00' --iso-8601=seconds)
wtype "Busy block"
wtype -k Tab
wtype "$busy_start"
wtype -k Tab
wtype "$busy_end"
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
wait_until "first task editor opens" 15 screen_contains "Add task"
wtype "Prepare acceptance task"
wtype -k Return
wait_until "first task enters the inbox" 15 screen_contains "Prepare acceptance task"

wtype -k Return
wait_until "second task editor opens" 15 screen_contains "Add task"
wtype "Follow-up acceptance task"
wtype -k Return
wait_until "second task enters the inbox" 15 screen_contains "Follow-up acceptance task"

first_task=$(jq -r '.tasks[] | select(.title == "Prepare acceptance task") | .id' "$STATE_FILE")
second_task=$(jq -r '.tasks[] | select(.title == "Follow-up acceptance task") | .id' "$STATE_FILE")
[[ -n $first_task && -n $second_task ]] || fail "acceptance tasks are persisted"

# Add task, Settings, first Edit, second Edit.
press_tabs 3
wtype -k Return
wait_until "second task editor reopens" 15 screen_contains "Edit task"
press_tabs 6
wtype -k Return
wtype "Prepare acceptance task"
wtype -k Return
press_tabs 1
wtype -k Return
wait_until "dependency is persisted" 15 jq -e --arg from "$first_task" --arg to "$second_task" 'any(.dependencies[]; .fromTaskId == $from and .toTaskId == $to)' "$STATE_FILE"
screenshot "success-calendar-planner-08-dependent-tasks"

# The solver runs automatically after the final input change. It must avoid
# the manual event and leave the calendar untouched until Apply schedule.
wait_until "automatic proposal is ready" 30 jq -e '.proposal.status == "ready" and (.proposal.baseInputRevision == .inputRevision)' "$STATE_FILE"
wait_until "proposal appears in planner" 15 screen_contains "Latest proposal"
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
press_tabs 4
wtype -k Return
wait_until "proposal review opens" 15 screen_contains "Apply schedule"
screenshot "success-calendar-planner-10-proposal-review"
wtype -k Return
wait_until "proposal is explicitly applied" 15 jq -e '.proposal.status == "applied" and ([.events[] | select(.origin == "planner")] | length) > 0' "$STATE_FILE"
screenshot "success-calendar-planner-11-applied-proposal"

# Restart the real shell, reopen the clock, and prove that applied events are
# state-file data rather than process-local UI state.
wtype -k Escape
omarchy-restart-shell
wait_until "shell responds after restart" 30 omarchy-shell shell ping
open_clock
wtype "a"
wait_until "agenda survives shell restart" 15 screen_contains "Agenda"
wait_until "applied event survives shell restart" 15 jq -e 'any(.events[]; .origin == "planner" and .taskId != null)' "$STATE_FILE"
screenshot "success-calendar-planner-12-restarted-agenda"

# Return the applied planner event to the inbox from the agenda. The planner
# event is ordered before the later manual busy block, so the first event
# action after the three agenda controls is the explicit Return to inbox.
press_tabs 3
wtype -k Return
wait_until "applied task returns to inbox" 15 jq -e --arg id "$first_task" 'any(.tasks[]; .id == $id and .state == "inbox")' "$STATE_FILE"
wait_until "return to inbox removes only the linked planner event" 15 jq -e --arg id "$first_task" 'all(.events[]; .origin != "planner" or .taskId != $id)' "$STATE_FILE"
pass "return to inbox removes only the linked planner event"
