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
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
for arg in "$@"; do
  [[ $arg == file=@* ]] && printf '%s\n' "${arg#file=@}" >"$OMARCHY_TEST_UPLOAD_PATH"
done
printf 'https://logs.omarchy.org/test\n'
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export HOME="$tmp_dir/home"
export XDG_RUNTIME_DIR="$tmp_dir/run"
export OMARCHY_TEST_UPLOAD_PATH="$tmp_dir/upload-path"

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
[[ $uploaded != /tmp/* ]] ||
  fail "the uploaded payload is staged outside /tmp" "uploaded: $uploaded"
pass "the uploaded payload is staged outside /tmp"

staging_dir=${uploaded%/*}
if [[ -d $staging_dir ]]; then
  fail "the staging directory is cleaned up after the upload" "left behind: $staging_dir"
fi
pass "the staging directory is cleaned up after the upload"
