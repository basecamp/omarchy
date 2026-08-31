#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const os = require('os')
const { execFileSync } = require('child_process')

const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// Run the real expression rather than a copy of it, so the fixtures below
// cannot drift away from what the lock screen actually executes.
const commandMatch = serviceQml.match(/command: (\["bash", "-c", "(?:[^"\\]|\\.)*"\])/g)
  .map((line) => JSON.parse(line.replace(/^command: /, '')))
  .find((command) => command[2].includes('fprintd-list'))

assert(commandMatch !== undefined, 'the fingerprint probe is a bash command in Service.qml')

const probeScript = commandMatch[2]
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchy-fingerprint-probe-'))

// PATH is reduced to the sandbox so a system fprintd-list cannot answer for a
// stub, and grep is linked in because the probe genuinely shells out to it.
const grepPath = execFileSync('bash', ['-c', 'command -v grep'], { encoding: 'utf8' }).trim()

function runProbe({ fprintdOutput, fprintdStatus = 0, pamConfig = true, fprintdListOnPath = true }) {
  const binDir = fs.mkdtempSync(path.join(workDir, 'bin-'))
  const pamPath = path.join(binDir, 'omarchy-lock-fingerprint')
  if (pamConfig) fs.writeFileSync(pamPath, '')

  fs.symlinkSync(grepPath, path.join(binDir, 'grep'))

  if (fprintdListOnPath) {
    const lines = fprintdOutput.split('\n').map((line) => `printf '%s\\n' ${JSON.stringify(line)}`)
    fs.writeFileSync(
      path.join(binDir, 'fprintd-list'),
      `#!/bin/bash\n${lines.join('\n')}\nexit ${fprintdStatus}\n`,
      { mode: 0o755 }
    )
  }

  // Only the PAM path is rewritten; the decision logic runs verbatim.
  const script = probeScript.split('/etc/pam.d/omarchy-lock-fingerprint').join(pamPath)

  return execFileSync('/bin/bash', ['-c', script], {
    env: { PATH: binDir, USER: 'tester' },
    encoding: 'utf8',
  }).trim()
}

const ENROLLED = [
  'found 1 devices',
  'Device at /net/reactivated/Fprint/Device/0',
  'Using device /net/reactivated/Fprint/Device/0',
  'Fingerprints for user tester on Goodix MOC Fingerprint Sensor (press):',
  ' - #0: right-index-finger',
].join('\n')

const NO_PRINTS = [
  'found 1 devices',
  'Device at /net/reactivated/Fprint/Device/0',
  'Using device /net/reactivated/Fprint/Device/0',
  'User tester has no fingers enrolled for Goodix MOC Fingerprint Sensor.',
].join('\n')

const UNREACHABLE =
  'Impossible to get devices: GDBus.Error:org.freedesktop.DBus.Error.NameHasNoOwner: ' +
  "Could not activate remote peer 'net.reactivated.Fprint': activation request failed"

try {
  assertEqual(
    runProbe({ fprintdOutput: ENROLLED }),
    'yes',
    'an enrolled print reads as configured'
  )

  // Both the negative message and the device name contain "finger", so a
  // looser match reports a reader the account cannot actually use.
  assertEqual(
    runProbe({ fprintdOutput: NO_PRINTS }),
    'no',
    'a user with no prints reads as not configured'
  )

  // The resume window: fprintd is D-Bus activated and the activation request
  // can fail outright while it is stopping or while systemd finishes resuming.
  assertEqual(
    runProbe({ fprintdOutput: UNREACHABLE, fprintdStatus: 1 }),
    'unknown',
    'an unreachable fprintd reads as unknown, not as unconfigured'
  )

  // fprintd-list returns 0 and 1 inconsistently for identical input
  // (fprintd 1.94.5), so the exit status must not decide this.
  assertEqual(
    runProbe({ fprintdOutput: ENROLLED, fprintdStatus: 1 }),
    'yes',
    'a non-zero exit alongside enrolled output still reads as configured'
  )

  assertEqual(
    runProbe({ fprintdOutput: ENROLLED, pamConfig: false }),
    'no',
    'a missing PAM config reads as not configured'
  )

  assertEqual(
    runProbe({ fprintdOutput: ENROLLED, fprintdListOnPath: false }),
    'no',
    'a missing fprintd-list reads as not configured'
  )
} finally {
  fs.rmSync(workDir, { recursive: true, force: true })
}

// An unknown answer must not reach fingerprintConfigured: that flag gates the
// retry in handleFingerprintFinished and the startFingerprint guard, so one
// miss would otherwise disable fingerprint for the rest of the lock.
assert(
  /if \(answer === "unknown"\) \{[\s\S]*?fingerprintProbeRetryTimer\.restart\(\)\s*\n\s*return/.test(serviceQml),
  'an unknown probe re-arms the probe retry instead of settling the answer'
)

assert(
  /root\.fingerprintProbeMisses \+= 1[\s\S]*?root\.fingerprintProbeMisses <= root\.fingerprintProbeMissLimit/.test(serviceQml),
  'the unknown retries are bounded by a miss limit'
)

assert(
  /fingerprintProbeRetryTimer[\s\S]*?interval: 1000/.test(serviceQml),
  'the probe retry is slower than the 250ms finger retry'
)

// Holding fingerprintConfigured true across an unknown keeps startFingerprint
// callable, so the 250ms retry has to be held off explicitly or it storms PAM
// subprocesses against a daemon that is not there.
assert(
  /answer === "unknown"[\s\S]*?fingerprintRetryTimer\.stop\(\)/.test(serviceQml),
  'an unknown probe stops the fast finger retry'
)

assert(
  /fingerprintConfigured && (?:root\.)?fingerprintProbeMisses === 0/.test(serviceQml) &&
    serviceQml.match(/fingerprintProbeMisses === 0/g).length === 2,
  'both retry re-arms are suppressed while a probe miss is outstanding'
)

assert(
  /resetAuthenticationState[\s\S]*?fingerprintProbeMisses = 0[\s\S]*?fingerprintProbeRetryTimer\.stop\(\)/.test(serviceQml),
  'unlocking clears the miss count and stops the probe retry'
)
JS
