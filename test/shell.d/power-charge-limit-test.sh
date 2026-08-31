#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const power = requireFromRoot('shell/plugins/panels/power/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/power/Panel.qml', 'utf8')

assertEqual(power.parseChargeLimit('80'), 80, 'charge limit parses a plain integer')
assertEqual(power.parseChargeLimit('90\n'), 90, 'charge limit trims trailing newline')
assertEqual(power.parseChargeLimit(''), null, 'charge limit rejects empty output')
assertEqual(power.parseChargeLimit('abc'), null, 'charge limit rejects non-numeric output')
assertEqual(power.parseChargeLimit('150'), null, 'charge limit rejects values above 100')
assertEqual(power.parseChargeLimit('-5'), null, 'charge limit rejects negative values')

assert(/command: \["omarchy-battery-limit-get"\]/.test(panelSource), 'charge limit reads via omarchy-battery-limit-get')
assert(/command = \["omarchy-battery-limit-set", String\(value\)\]/.test(panelSource), 'charge limit sets via omarchy-battery-limit-set')
assert(/command: \["omarchy-hw-battery-charge-limit"\]/.test(panelSource), 'charge limit probes support via omarchy-hw-battery-charge-limit')
assert(!/charge_control_end_threshold/.test(panelSource), 'charge limit does not hardcode the sysfs path')
assert(!/sudo/.test(panelSource), 'charge limit does not self-elevate in the shell')

assert(/root\.chargeLimitSupported = exitCode === 0/.test(panelSource), 'charge limit caches support from the probe exit code')
assert(/onOpenedChanged:[\s\S]*?chargeLimitCheckProc\.running = true/.test(panelSource), 'charge limit probes support once per panel open')
assert(/function refresh\(\) \{[\s\S]*?if \(chargeLimitSupported && !thresholdReadProc\.running\) thresholdReadProc\.running = true/.test(panelSource), 'charge limit refresh is gated on support')
assertEqual(panelSource.match(/visible: root\.chargeLimitSupported/g).length, 2, 'charge limit hides the separator and section when unsupported')
assert(/chargeLimitOptions: \[80, 90, 100\]/.test(panelSource), 'charge limit offers 80, 90, and 100 percent')
assert(/"CHARGE LIMIT — " \+ root\.chargeLimit \+ "%"/.test(panelSource), 'charge limit header shows the current limit')
JS
