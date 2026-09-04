#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
log="$tmp_dir/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"${OMARCHY_CLI_TEST_LOG:?}"
target=${1:-}
method=${2:-}

state='{"schemaVersion":1,"inputRevision":4,"settings":{"timezone":"Europe/Rome","availability":{"monday":[{"start":"09:00","end":"17:00"}]},"horizonDays":14,"slotMinutes":15,"solveSeconds":5,"priorityLowWeight":1,"priorityNormalWeight":5,"priorityHighWeight":25,"cognitiveEnabled":false,"lowWindowStart":"00:00","lowWindowEnd":"00:00","lowOutsidePenalty":0,"mediumWindowStart":"00:00","mediumWindowEnd":"00:00","mediumOutsidePenalty":0,"highWindowStart":"00:00","highWindowEnd":"00:00","highOutsidePenalty":0,"highStreakLimit":1,"recoveryMinutes":30,"excessHighPenalty":60},"events":[{"id":"event-1","title":"Busy","description":"","startAt":"2026-09-07T10:00:00+02:00","endAt":"2026-09-07T11:00:00+02:00","timezone":"Europe/Rome","allDay":false,"rrule":null,"origin":"manual","taskId":null,"proposalId":null,"createdAt":"2026-09-04T08:00:00Z","updatedAt":"2026-09-04T08:00:00Z"}],"tasks":[],"dependencies":[],"proposal":null}'

if [[ $target == omarchy.clock && $method == openView ]]; then
  [[ ${3:-} == plan ]] || exit 1
  printf 'ok\n'
  exit 0
fi

case "$method" in
status)
  jq -cn --argjson state "$state" '{state:$state,loaded:true,configured:true,solveState:"idle",error:"",errorOutput:""}'
  ;;
state)
  jq -cn --argjson state "$state" '{ok:true,state:$state}'
  ;;
addEvent)
  jq -e '.title == "New" and .startAt == "2026-09-08T10:00:00+02:00" and .endAt == "2026-09-08T11:00:00+02:00"' <<<"${3:-}" >/dev/null
  jq -cn --argjson state "$state" --argjson input "${3:-}" '{ok:true,state:($state | .events += [($input + {id:"event-new"})])}'
  ;;
addTask)
  jq -e '.title == "Task" and .durationMinutes == 45 and .priority == "high" and .deadlineKind == "none"' <<<"${3:-}" >/dev/null
  jq -cn --argjson state "$state" --argjson input "${3:-}" '{ok:true,state:($state | .tasks += [($input + {id:"task-new"})])}'
  ;;
setSettings)
  jq -e '.timezone == "Europe/Rome" and .availability.monday[0].start == "09:00"' <<<"${3:-}" >/dev/null
  jq -cn --argjson state "$state" '{ok:true,state:$state}'
  ;;
addDependency)
  [[ ${3:-} == first && ${4:-} == second ]] || exit 1
  jq -cn --argjson state "$state" '{ok:true,state:$state}'
  ;;
*)
  echo "unknown method: $target $method" >&2
  exit 1
  ;;
esac
SH
chmod +x "$stub_bin/omarchy-shell"

export OMARCHY_CLI_TEST_LOG="$log"
export PATH="$stub_bin:$ROOT/bin:$PATH"

events_json=$(OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" --json events)
jq -e 'length == 1 and .[0].title == "Busy"' <<<"$events_json" >/dev/null || fail "CLI lists events as JSON"
pass "CLI lists events as JSON"

OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" add-event \
  --title New --start 2026-09-08T10:00:00+02:00 --end 2026-09-08T11:00:00+02:00 >/dev/null
pass "CLI adds an event through the calendar service"

OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" add-task \
  --title Task --duration 45 --priority high >/dev/null
pass "CLI adds a planner task through the calendar service"

OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" settings \
  --timezone Europe/Rome --availability monday=09:00-17:00 >/dev/null
pass "CLI updates planner settings through the calendar service"

OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" dependency add first second >/dev/null
pass "CLI updates task dependencies through the calendar service"

OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-calendar" open plan >/dev/null
pass "CLI opens the Plan view in the existing clock popup"

grep -Fqx 'omarchy.calendar addEvent {"title":"New","startAt":"2026-09-08T10:00:00+02:00","endAt":"2026-09-08T11:00:00+02:00","allDay":false,"timezone":"Europe/Rome"}' "$log" || fail "CLI sends event JSON through IPC"
grep -Fqx 'omarchy.calendar addTask {"title":"Task","durationMinutes":45,"priority":"high","cognitiveLoad":"medium","deadlineKind":"none","earliestAt":null,"deadlineAt":null}' "$log" || fail "CLI sends task JSON through IPC"
pass "CLI sends native JSON requests through IPC"
