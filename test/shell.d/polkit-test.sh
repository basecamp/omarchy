#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const polkit = requireFromRoot('shell/plugins/polkit/PolkitModel.js')

assert(polkit.promptLooksFingerprint('Swipe your finger'), 'polkit detects fingerprint prompts')
assert(polkit.promptLooksFingerprint('fprintd verification'), 'polkit detects fprint prompts')
assert(!polkit.promptLooksFingerprint('Password:'), 'polkit ignores password prompts')
assert(polkit.promptLooksFido('Please touch your security key'), 'polkit detects FIDO prompts')

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

assertEqual(
  polkit.authenticationPresentation('fingerprint', true, true).method,
  'fingerprint',
  'polkit keeps a concrete fingerprint state when the lid is closed'
)
assertEqual(
  polkit.authenticationPresentation('fingerprint', false, false).method,
  'fingerprint',
  'polkit keeps a concrete fingerprint state when config is unavailable'
)
assert(
  polkit.authenticationPresentation('waiting', true, false).fingerprintLookahead,
  'polkit uses fingerprint lookahead only while waiting with an open configured reader'
)
assertEqual(
  polkit.authenticationPresentation('waiting', true, false).glyph,
  'fingerprint',
  'polkit shows the fingerprint lookahead glyph while waiting with an open configured reader'
)
assert(
  !polkit.authenticationPresentation('waiting', true, true).fingerprintLookahead,
  'polkit disables fingerprint lookahead when the lid is closed'
)
assertEqual(
  polkit.authenticationPresentation('waiting', true, true).glyph,
  'waiting',
  'polkit keeps the waiting glyph when the lid is closed'
)
assert(
  !polkit.authenticationPresentation('waiting', false, false).fingerprintLookahead,
  'polkit disables fingerprint lookahead when config is unavailable'
)
assertEqual(
  polkit.authenticationPresentation('waiting', false, false).glyph,
  'waiting',
  'polkit keeps the waiting glyph when config is unavailable'
)
assertEqual(
  polkit.authenticationPresentation('fido', true, false).method,
  'fido',
  'polkit does not override a concrete FIDO state with lookahead'
)
assertEqual(
  polkit.authenticationPresentation('password', true, false).method,
  'password',
  'polkit does not override a concrete password state with lookahead'
)

assertEqual(
  polkit.authenticationState('', 'Please touch the device.', false).method,
  'fido',
  'polkit classifies a U2F touch cue as FIDO'
)
assertEqual(
  polkit.authenticationState('ignored input prompt', 'Please touch the device.', false).prompt,
  'Please touch the device.',
  'polkit displays the supplementary FIDO cue while waiting'
)
assertEqual(
  polkit.authenticationState('', 'Swipe your finger', false).method,
  'fingerprint',
  'polkit classifies a fingerprint cue as fingerprint'
)
assertEqual(
  polkit.authenticationState('', 'Your finger was not centered, try touching the sensor again', false).method,
  'fingerprint',
  'polkit keeps a fingerprint retry cue as fingerprint'
)
assertEqual(
  polkit.authenticationState('', 'Remove your finger, and try touching the sensor again', false).method,
  'fingerprint',
  'polkit keeps a fingerprint removal cue as fingerprint'
)
assertEqual(
  polkit.authenticationState('Password:', '', true).method,
  'password',
  'polkit classifies a response request as password input'
)
assertEqual(
  polkit.authenticationState('', '', false).method,
  'waiting',
  'polkit classifies an empty non-interactive prompt as waiting'
)
assertEqual(
  polkit.authenticationState('', '', false).prompt,
  'Authentication in progress...',
  'polkit gives generic waiting a grounded fallback'
)
assertEqual(
  polkit.authenticationState('Swipe your finger', 'Please touch your U2F security key', false).method,
  'fido',
  'polkit prefers the U2F cue over a fingerprint input prompt'
)
assertEqual(
  polkit.authenticationState('Password:', 'Waiting for a device', true).prompt,
  'Password:',
  'polkit uses the input prompt for response requests'
)
JS
