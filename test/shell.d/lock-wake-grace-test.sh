#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(`${root}/shell/plugins/lock/Service.qml`, 'utf8')

assert(
  /readonly property int blankDelayMilliseconds: 5000/.test(serviceQml),
  'an untouched lock still blanks after five seconds'
)

assert(
  /readonly property int wakeBlankDelayMilliseconds: 30000/.test(serviceQml),
  'a DPMS wake gets enough time for slow displays to finish link training'
)

assert(
  /function runBlank\(\) \{\s*displayBlanked = true\s*wakeGraceUntil = 0/.test(serviceQml),
  'blanking records that the next activity is a hardware wake'
)

assert(
  /if \(displayBlanked\) wakeGraceUntil = Date\.now\(\) \+ wakeBlankDelayMilliseconds\s*displayBlanked = false/.test(serviceQml),
  'the first activity after blanking starts one wake grace window'
)

assert(
  /armBlankTimer\(Math\.max\(blankDelayMilliseconds, wakeGraceUntil - Date\.now\(\)\)\)/.test(serviceQml),
  'later wake activity cannot shorten the active grace window'
)

assert(
  /function handleSystemResume\(suspendedMilliseconds\)[\s\S]*wakeGraceUntil = Date\.now\(\) \+ wakeBlankDelayMilliseconds[\s\S]*armBlankTimer\(wakeBlankDelayMilliseconds\)/.test(serviceQml),
  'system resume starts the full slow-display wake grace'
)

assert(
  /id: systemResumeGapTimer[\s\S]*if \(elapsed > interval \+ 2000\) root\.handleSystemResume\(elapsed\)/.test(serviceQml),
  'a wall-clock gap detects resume even after the ordinary blank timer stopped'
)

assert(
  /if \(Date\.now\(\) - armedAt > interval \+ 2000\) \{\s*root\.handleSystemResume\(Date\.now\(\) - armedAt\)/.test(serviceQml),
  'a frozen active blank timer also enters the resume grace path'
)
JS
