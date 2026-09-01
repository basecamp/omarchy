#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
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

assertEqual(
  polkit.authorizationLabel("Authentication is needed to run `/usr/bin/true' as the super user", 'Codex'),
  "Codex wants: '/usr/bin/true'",
  'polkit attributes a pkexec message to the agent'
)
assertEqual(
  polkit.authorizationLabel('Authentication is required to change system settings', 'Codex'),
  'Authentication is required to change system settings',
  'polkit leaves non-pkexec messages stock even with an agent'
)
assertEqual(polkit.displayNameForAgent('codex'), 'Codex', 'polkit maps codex slug')
assertEqual(polkit.displayNameForAgent('claude'), 'Claude Code', 'polkit maps claude slug')
assertEqual(polkit.displayNameForAgent('omp'), 'Oh My Pi', 'polkit maps omp slug')
assertEqual(polkit.displayNameForAgent('nope'), '', 'polkit unknown slug stays empty')
assertEqual(polkit.displayNameForAgent(''), '', 'polkit empty slug stays empty')

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
JS
