#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const polkit = requireFromRoot('shell/plugins/polkit/PolkitModel.js')
const agentQml = fs.readFileSync(path.join(root, 'shell/plugins/polkit/PolkitAgent.qml'), 'utf8')

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
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_fprintd.so').fingerprint,
  true,
  'polkit detects fingerprint-only PAM capability'
)
assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_fprintd.so').fido,
  false,
  'polkit excludes FIDO from a fingerprint-only PAM stack'
)
assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_u2f.so').fido,
  true,
  'polkit detects U2F-only PAM capability'
)
assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_u2f.so').fingerprint,
  false,
  'polkit excludes fingerprint from a U2F-only PAM stack'
)
const clamshellCapabilities = polkit.authCapabilitiesFromPamConfig(`
auth [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth sufficient pam_fprintd.so
auth sufficient pam_u2f.so
`)
assert(clamshellCapabilities.fingerprint && clamshellCapabilities.fido, 'polkit detects both capabilities behind a clamshell gate')
const ignoredCapabilities = polkit.authCapabilitiesFromPamConfig(`
# auth sufficient pam_fprintd.so
account sufficient pam_u2f.so
session optional pam_fprintd.so
`)
assert(!ignoredCapabilities.fingerprint && !ignoredCapabilities.fido, 'polkit ignores commented and non-auth PAM lines')
assertEqual(ignoredCapabilities.methods.join(','), '', 'polkit omits commented and non-auth methods from order')

assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_fprintd.so\nauth sufficient pam_u2f.so').methods.join(','),
  'fingerprint,fido',
  'polkit preserves fingerprint-then-FIDO PAM order'
)
assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_u2f.so\nauth sufficient pam_fprintd.so').methods.join(','),
  'fido,fingerprint',
  'polkit preserves FIDO-then-fingerprint PAM order'
)
assertEqual(
  polkit.authCapabilitiesFromPamConfig('auth sufficient pam_u2f.so\nauth sufficient pam_u2f.so\nauth sufficient pam_fprintd.so\nauth sufficient pam_fprintd.so').methods.join(','),
  'fido,fingerprint',
  'polkit lists duplicate physical PAM modules once'
)

const frenchFingerprintCue = 'Placez votre doigt sur le lecteur d’empreintes'
assertEqual(
  polkit.authenticationState('', frenchFingerprintCue, false).method,
  'physical',
  'polkit classifies a French fingerprint cue as physical auth'
)
assertEqual(
  polkit.authenticationState('', frenchFingerprintCue, false).prompt,
  frenchFingerprintCue,
  'polkit preserves a French physical-auth cue verbatim'
)
const customU2fCue = 'Custom token challenge: tap any enrolled device'
assertEqual(
  polkit.authenticationState('', customU2fCue, false).method,
  'physical',
  'polkit classifies a custom U2F cue as physical auth'
)
assertEqual(
  polkit.authenticationState('ignored input prompt', customU2fCue, false).prompt,
  customU2fCue,
  'polkit prefers the supplementary physical-auth cue'
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
  polkit.authenticationState('Input cue', '', false).prompt,
  'Input cue',
  'polkit falls back to the input prompt for physical auth'
)
assertEqual(
  polkit.authenticationState('Password:', 'Waiting for a device', true).prompt,
  'Password:',
  'polkit uses the input prompt for response requests'
)

assert(
  agentQml.includes('/sys/class/hidraw/hidraw*') && agentQml.includes('udevadm info --query=property --path'),
  'polkit passively probes hidraw properties for a FIDO token'
)
assert(
  agentQml.includes('ID_SECURITY_TOKEN=1') && agentQml.includes('ID_FIDO_TOKEN=1'),
  'polkit recognizes both security-token and FIDO-token udev markers'
)
assert(
  /readonly property var activeMethods:[\s\S]*?m === "fido" && \(!fidoStateKnown \|\| !fidoTokenConnected/.test(agentQml),
  'polkit exposes FIDO only after its connected state is known'
)
assert(
  /function beginFlow\(\)\s*\{[^}]*refreshFidoState\(\)/.test(agentQml),
  'polkit refreshes FIDO presence for each authentication flow'
)
JS
