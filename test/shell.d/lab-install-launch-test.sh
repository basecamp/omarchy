#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
export OMARCHY_PATH="$ROOT"
source "$ROOT/bin/omarchy-lab-install-launch"
test_tmp=$(mktemp -d)
trap 'if [[ -f $test_tmp/installer-pid ]]; then kill "$(cat "$test_tmp/installer-pid")" 2>/dev/null || true; fi; rm -rf -- "$test_tmp"' EXIT
export XDG_RUNTIME_DIR="$test_tmp/runtime" LAB_INSTALL_TEST_DIR="$test_tmp"
mkdir -p "$XDG_RUNTIME_DIR" "$test_tmp/Lab package/bin"
OMARCHY_PATH="$test_tmp/Lab package"
cat >"$OMARCHY_PATH/bin/omarchy-lab-vm" <<'SH'
#!/bin/bash
[[ $1 == "install" && -t 0 && -t 1 ]] || exit 2
echo "$$" >"$LAB_INSTALL_TEST_DIR/installer-pid"
exec sleep 30
SH
chmod +x "$OMARCHY_PATH/bin/omarchy-lab-vm"

(
  launch_lifecycle_terminal() {
    local command
    printf -v command '%q ' "$@"
    script -q -e -c "$command" /dev/null
  }
  SECONDS=0
  launch_installer >"$test_tmp/result"
  ((SECONDS < 5)) || fail "launch waited for installation completion"
  [[ -f $test_tmp/installer-pid ]] || fail "terminal did not enter the installer"
  kill -0 "$(cat "$test_tmp/installer-pid")" || fail "installer died after handoff"
  rg -q 'Lab action opened' "$test_tmp/result" || fail "missing startup acknowledgement"
)
pass "real PTY startup acknowledges before installer exit, with spaces in package path"

(
  launch_lifecycle_terminal() { echo 'terminal launcher unavailable' >&2; return 7; }
  if launch_installer >"$test_tmp/output" 2>"$test_tmp/error"; then fail "launch failure reported success"; fi
  rg -q 'terminal launcher unavailable' "$test_tmp/error" || fail "launcher error was lost"
)
pass "terminal launch failure is propagated with actionable error"

(
  launch_lifecycle_terminal() { return 0; }
  sleep() { command sleep 0.001; }
  if launch_installer >"$test_tmp/output" 2>"$test_tmp/error"; then fail "early launcher exit counted as readiness"; fi
  rg -q 'did not become ready' "$test_tmp/error" || fail "missing bounded timeout error"
)
pass "launcher success without a terminal times out instead of dismissing the panel"

(
  launch_lifecycle_terminal() { "$@"; }
  if launch_installer >"$test_tmp/output" 2>"$test_tmp/error"; then fail "non-terminal process counted as readiness"; fi
)
[[ -z $(ls -A "$XDG_RUNTIME_DIR") ]] || fail "startup handshake files leaked"
pass "non-TTY launch rejected and private handshake files cleaned up"

(
  launch_lifecycle_terminal() {
    printf '%s\0' "$@" >"$test_tmp/terminal-args"
    touch "$5/ready"
  }
  for entry in 'vm reset' 'gold promote' 'gold rebuild' 'checkpoint create' 'checkpoint restore' 'resource set' 'network nat' 'network isolated' 'network offline' 'scenario run'; do
    read -r family action <<<"$entry"
    launch_terminal "omarchy-lab-$family" "$action" 'value with spaces' '--yes' >/dev/null
    mapfile -d '' -t captured <"$test_tmp/terminal-args"
    [[ ${captured[5]} == "$OMARCHY_PATH/bin/omarchy-lab-$family" && ${captured[6]} == "$action" && ${captured[7]} == 'value with spaces' && ${captured[8]} == '--yes' ]] || fail "terminal arguments changed: $entry"
  done
  if launch_terminal /bin/bash -c true; then fail "arbitrary command accepted"; fi
  if launch_terminal omarchy-lab-health --json; then fail "health poll accepted"; fi
  if launch_terminal omarchy-lab-gold status; then fail "status poll accepted"; fi
)
pass "privileged terminal actions preserve arguments and reject arbitrary commands and polling"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const Model = requireFromRoot('shell/plugins/panels/lab/Model.js')
const panel = fs.readFileSync(path.join(root, 'shell/plugins/panels/lab/Panel.qml'), 'utf8')
const names = ['openInstaller', 'runCommand', 'actionFailedToStart', 'armOrRun', 'terminalButtonText']
const context = {
  Model, busy: false, actionProc: {running: false}, armedAction: '', confirmTimer: {stop() {}, restart() {}},
  errorText: '', actionOutput: '', stderrText: '', actionLabel: '', closeAfterAction: false,
  labCommand: name => '/plugin/bin/' + name
}
vm.createContext(context)
for (const name of names) {
  const match = panel.match(new RegExp('  function ' + name + '\\([^]*?\\n  }'))
  assert(match, `${name} exists`)
  vm.runInContext(match[0], context)
}
context.openInstaller()
assert(context.busy, 'launch is immediately busy')
assertEqual(context.actionLabel, 'Opening installer', 'launch state has a clear label')
assert(context.closeAfterAction, 'successful readiness dismisses the panel')
assertEqual(context.actionProc.command[0], '/plugin/bin/omarchy-lab-install-launch', 'uses readiness helper')
context.actionProc.command = ['sentinel']
context.openInstaller()
assertEqual(context.actionProc.command[0], 'sentinel', 'double click cannot start another process')
context.actionProc.running = false
context.actionFailedToStart()
assert(!context.busy && !context.closeAfterAction && context.errorText, 'spawn failure unlocks retry without closing')
context.openInstaller()
assertEqual(context.errorText, '', 'retry clears stale error')
assert(panel.includes('root.installerOpening ? "Opening installer…" : "Install Lab VM"'), 'button reflects launch state')
assert(panel.includes('visible: root.inlineInstallError'), 'launch error shown beside button')
assert(panel.includes('visible: root.errorText !== "" && !root.inlineInstallError'), 'launch error is not duplicated in global banner')
assert(panel.includes('else if (root.closeAfterAction) root.dismiss()'), 'only successful exit dismisses')

for (const [command, args] of [
  ['/plugin/bin/omarchy-lab-viewer', ['reset']],
  ['omarchy-lab-gold', ['promote', '--yes']],
  ['omarchy-lab-gold', ['rebuild', '--yes']],
  ['omarchy-lab-checkpoint', ['create', 'before']],
  ['omarchy-lab-checkpoint', ['restore', 'before', '--yes']],
  ['omarchy-lab-resource', ['set', 'custom', '4', '8']],
  ['omarchy-lab-network', ['nat']],
  ['omarchy-lab-network', ['isolated']],
  ['omarchy-lab-network', ['offline']],
  ['omarchy-lab-scenario', ['run', 'checkpoint-deploy', 'feature/demo', '--branch']]
]) {
  context.busy = false
  context.actionProc.running = false
  context.armedAction = ''
  context.actionProc.command = ['sentinel']
  const key = args[0]
  context.armOrRun(key, command, args, key)
  assertEqual(context.actionProc.command[0], 'sentinel', `${key} first click only confirms`)
  context.armOrRun(key, command, args, key)
  assertEqual(context.actionProc.command[0], '/plugin/bin/omarchy-lab-terminal-launch', `${key} hands off after confirmation`)
  assert(context.closeAfterAction, `${key} dismisses after terminal readiness`)
  assertEqual(context.terminalButtonText(key, 'Original'), 'Opening terminal…', `${key} exposes opening state`)
  assertDeepEqual(Array.from(context.actionProc.command).slice(2), args, `${key} preserves original arguments`)
}
for (const [command, args] of [
  ['omarchy-lab-health', ['--json']], ['omarchy-lab-network', ['status', '--json']],
  ['omarchy-lab-resource', ['status', '--json']], ['omarchy-lab-checkpoint', ['list', '--json']],
  ['omarchy-lab-gold', ['status', '--json']], ['omarchy-lab-viewer', ['aspect', '16:9']],
  ['omarchy-lab-transfer', ['clipboard-to', '--host']]
]) assertEqual(Model.terminalCommand(command, args), null, `${command} ${args[0]} stays inline`)
JS
