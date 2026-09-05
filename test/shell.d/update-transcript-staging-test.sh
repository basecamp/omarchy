#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin" "$tmp_dir/run" "$tmp_dir/home"

# omarchy-update re-execs itself through script(1) before it does anything
# else, so a stub that records the transcript path and exits exercises the
# wrapper without running an update.
cat >"$stub_bin/script" <<'SH'
#!/bin/bash
printf '%s' "${@: -1}" >"$OMARCHY_TEST_TRANSCRIPT_PATH"
exit 0
SH
chmod +x "$stub_bin/script"

export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
export XDG_RUNTIME_DIR="$tmp_dir/run"
export OMARCHY_TEST_TRANSCRIPT_PATH="$tmp_dir/transcript-path"
unset XDG_STATE_HOME

"$ROOT/bin/omarchy-update" >/dev/null 2>&1

transcript=$(<"$OMARCHY_TEST_TRANSCRIPT_PATH")

[[ $transcript == "$XDG_RUNTIME_DIR/omarchy-update.log" ]] ||
  fail "the update transcript lives under the per-user runtime directory" "$transcript"
pass "the update transcript lives under the per-user runtime directory"

[[ -f $transcript ]] ||
  fail "the transcript file exists before script(1) opens it" "$transcript"
pass "the transcript file exists before script(1) opens it"

mode=$(stat -c '%a' "$transcript" 2>/dev/null || stat -f '%Lp' "$transcript")
[[ $mode == "600" ]] ||
  fail "the transcript is readable only by its owner" "mode: $mode"
pass "the transcript is readable only by its owner"

# Without a session runtime dir the transcript falls back to the state
# directory, and omarchy-update-analyze-logs must resolve to the same file.
env -u XDG_RUNTIME_DIR "$ROOT/bin/omarchy-update" >/dev/null 2>&1

transcript=$(<"$OMARCHY_TEST_TRANSCRIPT_PATH")

[[ $transcript == "$HOME/.local/state/omarchy/omarchy-update.log" ]] ||
  fail "without a runtime dir the transcript falls back to the state directory" "$transcript"
pass "without a runtime dir the transcript falls back to the state directory"

for file in bin/omarchy-update bin/omarchy-update-analyze-logs; do
  if grep -q '/tmp/omarchy-update.log' "$ROOT/$file"; then
    fail "$file no longer names a world-writable transcript path"
  fi
done
pass "neither update script names a world-writable transcript path"

# analyze-logs reads the same file the transcript was written to.
printf '%s\n' "(1/3) Updating linux initcpios" >"$XDG_RUNTIME_DIR/omarchy-update.log"

output=$("$ROOT/bin/omarchy-update-analyze-logs" 2>&1)
[[ $output == *"Initramfs"* ]] ||
  fail "analyze-logs flags an initramfs failure in the transcript" "$output"
pass "analyze-logs flags an initramfs failure in the transcript"

printf '%s\n' "Initcpio image generation successful" >>"$XDG_RUNTIME_DIR/omarchy-update.log"

output=$("$ROOT/bin/omarchy-update-analyze-logs" 2>&1)
[[ -z $output ]] ||
  fail "analyze-logs stays quiet once the initramfs succeeded" "$output"
pass "analyze-logs stays quiet once the initramfs succeeded"

# The fallback branch has to agree too, or an update without a session would
# write a transcript its own analyzer cannot find.
printf '%s\n' "(1/3) Updating linux initcpios" >"$HOME/.local/state/omarchy/omarchy-update.log"

output=$(env -u XDG_RUNTIME_DIR -u XDG_STATE_HOME "$ROOT/bin/omarchy-update-analyze-logs" 2>&1)
[[ $output == *"Initramfs"* ]] ||
  fail "analyze-logs resolves the fallback transcript the update wrote" "$output"
pass "analyze-logs resolves the fallback transcript the update wrote"

# A standalone run with no transcript behind it is a no-op, not a grep error.
fresh_run="$tmp_dir/run-empty"
mkdir -p "$fresh_run"

output=$(XDG_RUNTIME_DIR="$fresh_run" "$ROOT/bin/omarchy-update-analyze-logs" 2>&1)
[[ -z $output ]] ||
  fail "analyze-logs without a transcript is silent" "$output"
pass "analyze-logs without a transcript is silent"

docs="$ROOT/docs/update-process.md"
python3 - "$docs" <<'PY' || fail "the failure-output list item names both transcript paths on one line"
import sys

items = [
    line for line in open(sys.argv[1])
    if line.startswith("- A failure should leave")
]
if len(items) != 1:
    raise SystemExit(1)
if "XDG_RUNTIME_DIR" not in items[0] or "XDG_STATE_HOME" not in items[0]:
    raise SystemExit(1)
PY
pass "the failure-output list item names both transcript paths on one line"

python3 - "$docs" <<'PY' || fail "the omarchy-update flow documents the no-session transcript fallback"
import sys

text = open(sys.argv[1]).read()
start = text.find("## Path 1:")
end = text.find("## Path 2:")
block = text[start:end]
fence = block.split("```text", 1)[1].split("```", 1)[0]
if "XDG_RUNTIME_DIR" not in fence or "XDG_STATE_HOME" not in fence:
    raise SystemExit(1)
PY
pass "the omarchy-update flow documents the no-session transcript fallback"
