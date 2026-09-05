#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin" "$tmp_dir/run" "$tmp_dir/home"

for stub in inxi journalctl expac pacman comm sort ping fastfetch uname; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$stub"
done

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stub_bin/dmesg" <<'SH'
#!/bin/bash
printf '%s\n' "secret kernel ring buffer"
SH

# The upload is the point of the staging file, so capture what curl was handed
# rather than sending anything.
# The staging directory is removed when the upload exits, so the mode has to be
# read here, while the payload still exists.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
for arg in "$@"; do
  if [[ $arg == file=@* ]]; then
    payload="${arg#file=@}"
    printf '%s\n' "$payload" >"$OMARCHY_TEST_UPLOAD_PATH"
    stat -c '%a' "${payload%/*}" >"$OMARCHY_TEST_UPLOAD_MODE" 2>/dev/null ||
      stat -f '%Lp' "${payload%/*}" >"$OMARCHY_TEST_UPLOAD_MODE" 2>/dev/null || true
  fi
done
printf 'https://logs.omarchy.org/test\n'
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
export XDG_RUNTIME_DIR="$tmp_dir/run"
export OMARCHY_TEST_UPLOAD_PATH="$tmp_dir/upload-path"
export OMARCHY_TEST_UPLOAD_MODE="$tmp_dir/upload-mode"

# omarchy-debug: the log holds sudo dmesg and the journal, so it must not be
# staged under a name every account on the machine can predict and read.
"$ROOT/bin/omarchy-debug" --print >/dev/null

[[ -f $XDG_RUNTIME_DIR/omarchy-debug.log ]] ||
  fail "omarchy-debug writes its log under the per-user runtime directory" "$(ls -a "$XDG_RUNTIME_DIR")"
pass "omarchy-debug writes its log under the per-user runtime directory"

mode=$(stat -c '%a' "$XDG_RUNTIME_DIR/omarchy-debug.log" 2>/dev/null || stat -f '%Lp' "$XDG_RUNTIME_DIR/omarchy-debug.log")
[[ $mode == "600" ]] ||
  fail "the debug log is readable only by its owner" "mode: $mode"
pass "the debug log is readable only by its owner"

grep -Fq 'secret kernel ring buffer' "$XDG_RUNTIME_DIR/omarchy-debug.log" ||
  fail "the debug log still collects what it collected before"
pass "the debug log still collects what it collected before"

if grep -q '/tmp/omarchy-debug.log' "$ROOT/bin/omarchy-debug"; then
  fail "omarchy-debug no longer names a world-writable path"
fi
pass "omarchy-debug no longer names a world-writable path"

# omarchy-upload-log stages the payload it publishes; the same reasoning
# applies, and there the file is also swappable between the last write and the
# upload.
"$ROOT/bin/omarchy-upload-log" system-info >/dev/null

uploaded=$(<"$OMARCHY_TEST_UPLOAD_PATH")
staging_dir=${uploaded%/*}

# mktemp still puts its directory under /tmp; the boundary is that the
# directory is unpredictable and only its owner can enter it, not that the
# path leaves /tmp behind.
[[ $uploaded != "/tmp/upload-log.txt" && $staging_dir != "/tmp" ]] ||
  fail "the uploaded payload is not staged at a shared, predictable name" "uploaded: $uploaded"
pass "the uploaded payload is not staged at a shared, predictable name"

staging_mode=$(<"$OMARCHY_TEST_UPLOAD_MODE")
[[ $staging_mode == "700" ]] ||
  fail "the staging directory is reachable only by its owner" "mode: ${staging_mode:-unreadable}"
pass "the staging directory is reachable only by its owner"

if [[ -d $staging_dir ]]; then
  fail "the staging directory is cleaned up after the upload" "left behind: $staging_dir"
fi
pass "the staging directory is cleaned up after the upload"

# A directory at the log path is the one shape `install` accepts without
# producing the file, so the guard has to be the thing that catches it --
# otherwise `--print` exits 0 having printed nothing, which is what a caller
# reads as a successful empty diagnostic.
blocked_runtime="$tmp_dir/blocked"
mkdir -p "$blocked_runtime/omarchy-debug.log"
blocked_out=$(XDG_RUNTIME_DIR="$blocked_runtime" "$ROOT/bin/omarchy-debug" --no-sudo --print 2>/dev/null) && blocked_status=0 || blocked_status=$?

if (( blocked_status == 0 )) || [[ -n $blocked_out ]]; then
  fail "omarchy-debug fails loudly when the log file cannot be created" "status: $blocked_status, bytes: ${#blocked_out}"
fi
pass "omarchy-debug fails loudly when the log file cannot be created"
