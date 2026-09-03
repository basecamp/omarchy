#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Custom command modules derive moduleName and settings from their layout entry
# as readonly bindings. ModuleSlot.injectProps used to assign those same names
# unconditionally whenever `"moduleName" in target`, which throws:
#   TypeError: Cannot assign to read-only property "moduleName"
# on every load / shell.json reload. The module still rendered because it never
# needed the injection; the assignment was pure log noise that also aborted
# before the settings write. Guard the writes so readonly targets are skipped.

bar_qml="$ROOT/shell/plugins/bar/Bar.qml"
[[ -f $bar_qml ]] || fail "bar QML is present"

ROOT="$ROOT" python3 - "$bar_qml" <<'PY' || fail "command module injectProps tolerates readonly moduleName/settings"
import re
import sys
from pathlib import Path

bar_path = Path(sys.argv[1])
bar = bar_path.read_text()

custom_start = bar.find("component CustomCommandModule:")
if custom_start < 0:
    print("CustomCommandModule is not defined on the bar", file=sys.stderr)
    sys.exit(1)
print("ok - CustomCommandModule is defined on the bar")

# Body through the component's closing brace (indent of two spaces).
custom_end = bar.find("\n  }\n", custom_start)
custom_body = bar[custom_start:custom_end + 4]

if not re.search(r"readonly property string moduleName:\s*root\.entryId\(entry\)", custom_body):
    print("CustomCommandModule must derive readonly moduleName from its entry", file=sys.stderr)
    sys.exit(1)
print("ok - CustomCommandModule derives readonly moduleName from its entry")

if not re.search(r"readonly property var settings:\s*root\.entrySettings\(entry\)", custom_body):
    print("CustomCommandModule must derive readonly settings from its entry", file=sys.stderr)
    sys.exit(1)
print("ok - CustomCommandModule derives readonly settings from its entry")

slot_start = bar.find("component ModuleSlot:")
if slot_start < 0:
    print("ModuleSlot is not defined on the bar", file=sys.stderr)
    sys.exit(1)
print("ok - ModuleSlot is defined on the bar")

slot_body = bar[slot_start:custom_start]
inject = re.search(r"function injectProps\(\)\s*\{([\s\S]*?)\n    \}", slot_body)
if not inject:
    print("ModuleSlot does not define injectProps", file=sys.stderr)
    sys.exit(1)
print("ok - ModuleSlot defines injectProps")
body = inject.group(1)

# Bare `if ("moduleName" in target) target.moduleName = ...` is the failure
# mode: `in` is true for readonly props and the assignment throws TypeError,
# aborting injectProps before settings is written.
bare_module = bool(re.search(r'if\s*\(\s*"moduleName"\s+in\s+target\s*\)\s*target\.moduleName\s*=', body))
bare_settings = bool(re.search(r'if\s*\(\s*"settings"\s+in\s+target\s*\)\s*target\.settings\s*=', body))
try_module = bool(re.search(r"try\s*\{[\s\S]*?target\.moduleName\s*=[\s\S]*?\}\s*catch", body))
try_settings = bool(re.search(r"try\s*\{[\s\S]*?target\.settings\s*=[\s\S]*?\}\s*catch", body))
# Skipping injection for command modules is also correct: they bind bar,
# moduleName, and settings themselves from entry.
skips_command = bool(re.search(r"if\s*\(\s*commandCustom\s*\)\s*return", body))

module_ok = (not bare_module and "moduleName" in body) or try_module or skips_command
settings_ok = (not bare_settings and "settings" in body) or try_settings or skips_command

if not module_ok:
    print(
        "injectProps must not bare-assign moduleName on targets that may be readonly",
        file=sys.stderr,
    )
    sys.exit(1)
print("ok - injectProps does not bare-assign readonly moduleName")

if not settings_ok:
    print(
        "injectProps must not bare-assign settings on targets that may be readonly",
        file=sys.stderr,
    )
    sys.exit(1)
print("ok - injectProps does not bare-assign readonly settings")

# Registered BarWidget modules still need the injection contract.
if '"bar" in target' not in body and not skips_command:
    # When command modules are skipped early, bar injection still runs for
    # registered/qml paths via the same function body after the guard.
    if 'target.bar' not in body:
        print("injectProps must still offer bar to modules that declare it", file=sys.stderr)
        sys.exit(1)
if "moduleName" not in body:
    print("injectProps must still handle moduleName for injectable modules", file=sys.stderr)
    sys.exit(1)
if "settings" not in body:
    print("injectProps must still handle settings for injectable modules", file=sys.stderr)
    sys.exit(1)
print("ok - injectProps still injects bar/moduleName/settings for writable modules")
PY

pass "command module injectProps tolerates readonly moduleName/settings"
