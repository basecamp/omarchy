#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const polkit = requireFromRoot('shell/plugins/polkit/PolkitModel.js')

assert(polkit.promptLooksFingerprint('Swipe your finger'), 'polkit detects fingerprint prompts')
assert(polkit.promptLooksFingerprint('fprintd verification'), 'polkit detects fprint prompts')
assert(!polkit.promptLooksFingerprint('Password:'), 'polkit ignores password prompts')

assertEqual(
  polkit.authorizationLabel("Authentication is needed to run `/usr/bin/true' as the super user"),
  "Authorize running '/usr/bin/true'",
  'polkit shortens the standard pkexec message'
)
assertEqual(
  polkit.authorizationLabel('Authentication is required to change system settings'),
  'Authentication is required to change system settings',
  'polkit preserves custom authorization messages'
)

assert(
  polkit.fingerprintConfiguredFromPamConfig(`
# comment
auth sufficient pam_fprintd.so
auth include system-auth
`),
  'polkit detects fingerprint in a PAM config'
)
assert(
  polkit.fingerprintConfiguredFromPamConfig(`
auth [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth sufficient pam_fprintd.so
auth required pam_unix.so
`),
  'polkit detects fingerprint even behind a clamshell gate'
)
assert(
  !polkit.fingerprintConfiguredFromPamConfig(`
account include system-auth
auth include system-auth
auth required pam_unix.so
`),
  'polkit reports no fingerprint when pam_fprintd is absent'
)

// Justification chip structure (#9872): long pkexec argv must wrap inside a
// readable width cap instead of middle-eliding inside a fixed single-line height.
const agentQml = fs.readFileSync(path.join(root, 'shell/plugins/polkit/PolkitAgent.qml'), 'utf8')

const justificationStart = agentQml.indexOf('id: justificationText')
assert(justificationStart !== -1, 'polkit agent declares justificationText')
const justificationBlock = agentQml.slice(justificationStart, justificationStart + 900)

assert(
  /wrapMode:\s*Text\.Wrap\b/.test(justificationBlock),
  'polkit justification wraps long authorization text'
)
assert(
  /maximumLineCount:\s*\d+/.test(justificationBlock),
  'polkit justification caps line count so pathological input cannot grow page-tall'
)
assert(
  /textFormat:\s*Text\.PlainText/.test(justificationBlock),
  'polkit justification stays plain text'
)
assert(
  !/elide:\s*Text\.ElideMiddle/.test(justificationBlock),
  'polkit justification does not middle-elide (hides the important middle of a command)'
)
// ElideRight is only acceptable as the overflow policy past maximumLineCount.
assert(
  /elide:\s*Text\.ElideRight/.test(justificationBlock),
  'polkit justification elides at the end only after the line cap'
)

const boxStart = agentQml.indexOf('id: justificationBox')
assert(boxStart !== -1, 'polkit agent declares justificationBox')
const boxBlock = agentQml.slice(boxStart, justificationStart + 900)

assert(
  /maxTextWidth:/.test(boxBlock),
  'polkit justification bounds width to a readable column'
)
assert(
  /Style\.space\(480\)/.test(boxBlock),
  'polkit justification width cap stays well below full-panel width'
)
assert(
  !/height:\s*Style\.space\(28\)\s*$/m.test(boxBlock.split('Text {')[0]),
  'polkit justification box height is not fixed at a single Style.space(28) line'
)
assert(
  /Math\.max\(\s*Style\.space\(28\),\s*justificationText\.(height|implicitHeight)/.test(boxBlock),
  'polkit justification box height follows wrapped text with a single-line floor'
)
assert(
  /fingerprintMode/.test(agentQml) && /OpticalGlyph/.test(agentQml),
  'polkit keeps the fingerprint-mode card path intact'
)
JS
