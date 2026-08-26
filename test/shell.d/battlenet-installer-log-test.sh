#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin" "$tmp_dir/home" "$tmp_dir/tmpdir"

for stub in omarchy-pkg-add omarchy-install-gaming-gpu-lib32 update-desktop-database; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$stub"
done

# The real download is a Windows installer fetched over the network; hand curl
# a stub that just creates the file it was told to write.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
out=""
grab=0
for arg in "$@"; do
  if ((grab)); then out="$arg"; grab=0; fi
  [[ $arg == "--output" ]] && grab=1
done
[[ -n $out ]] && : >"$out"
SH

# setsid -f detaches the wizard; run it in the foreground instead so the
# transcript is complete before the assertions look at it.
cat >"$stub_bin/setsid" <<'SH'
#!/bin/bash
[[ ${1:-} == "-f" ]] && shift
exec "$@"
SH

cat >"$stub_bin/umu-run" <<'SH'
#!/bin/bash
printf 'stub installer output\n'
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
export OMARCHY_PATH="$ROOT"
export TMPDIR="$tmp_dir/tmpdir"

output=$("$ROOT/bin/omarchy-install-gaming-battlenet" 2>&1)

log=$(grep '^Installer log: ' <<<"$output" | head -n1 | sed 's/^Installer log: //')
[[ -n $log ]] ||
  fail "the installer still reports where its log went" "$output"
pass "the installer still reports where its log went"

[[ $log != "/tmp/omarchy-battlenet-installer.log" ]] ||
  fail "the installer log is not a fixed world-writable name" "$log"
pass "the installer log is not a fixed world-writable name"

[[ $log == "$TMPDIR"/omarchy-battlenet-installer.* ]] ||
  fail "the installer log is an unpredictable name under TMPDIR" "$log"
pass "the installer log is an unpredictable name under TMPDIR"

[[ -f $log && $(<"$log") == *"stub installer output"* ]] ||
  fail "the wizard's output still lands in the log" "${log:+$(<"$log")}"
pass "the wizard's output still lands in the log"

mode=$(stat -c '%a' "$log" 2>/dev/null || stat -f '%Lp' "$log")
[[ $mode == "600" ]] ||
  fail "the installer log is readable only by its owner" "mode: $mode"
pass "the installer log is readable only by its owner"

if grep -q '/tmp/omarchy-battlenet-installer.log' "$ROOT/bin/omarchy-install-gaming-battlenet"; then
  fail "the installer script no longer names a world-writable log path"
fi
pass "the installer script no longer names a world-writable log path"
