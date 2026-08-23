#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "pomodoro transitions" <<'JS'
const pomodoro = requireFromRoot('shell/plugins/panels/pomodoro/Model.js')

assertEqual(pomodoro.advancePhase("custom", 0, 4, true), "focus", "pomodoro clears custom timer to focus")
assertEqual(pomodoro.advancePhase("shortBreak", 0, 4, true), "focus", "pomodoro goes back to focus after short break")
assertEqual(pomodoro.advancePhase("longBreak", 4, 4, true), "focus", "pomodoro goes back to focus after long break")
assertEqual(pomodoro.advancePhase("focus", 1, 4, true), "shortBreak", "pomodoro short breaks after 1st session")
assertEqual(pomodoro.advancePhase("focus", 2, 4, true), "shortBreak", "pomodoro short breaks after 2nd session")
assertEqual(pomodoro.advancePhase("focus", 3, 4, true), "shortBreak", "pomodoro short breaks after 3rd session")
assertEqual(pomodoro.advancePhase("focus", 4, 4, true), "longBreak", "pomodoro long breaks after 4th session")

assertEqual(pomodoro.getPhaseSecs("focus", 1500, 300, 900, 10), 1500, "pomodoro returns focus secs")
assertEqual(pomodoro.getPhaseSecs("custom", 1500, 300, 900, 10), 600, "pomodoro returns custom secs")
assertEqual(pomodoro.advancePhase("focus", 4, 4, false), "shortBreak", "pomodoro short breaks if focus is skipped even at long break threshold")
JS
