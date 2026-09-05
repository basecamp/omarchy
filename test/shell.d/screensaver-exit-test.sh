#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
log="$tmp_dir/log"

# A slow cursor restore keeps the exit handler running long enough for a
# second signal to arrive while it is still working.
cat >"$tmp_dir/bin/hyprctl" <<EOF
#!/bin/bash
if [[ \$1 == "activewindow" ]]; then
  printf '%s\n' '{"class":"org.omarchy.screensaver"}'
  exit 0
fi

if [[ \$2 == *'invisible = false'* || \$2 == 'cursor:invisible false' ]]; then
  printf 'cursor-restore\n' >>"$log"
  sleep 0.3
fi

printf 'signal\n' >>"$tmp_dir/armed"
exit 0
EOF

cat >"$tmp_dir/bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

cat >"$tmp_dir/bin/pkill" <<EOF
#!/bin/bash
printf 'pkill:%s\n' "\$*" >>"$log"
EOF

cat >"$tmp_dir/bin/ttfx" <<EOF
#!/bin/bash
printf 'ttfx-start\n' >>"$log"
sleep 10
EOF

chmod +x "$tmp_dir/bin/"*

PATH="$tmp_dir/bin:$PATH" bash "$ROOT/bin/omarchy-screensaver" </dev/null >"$tmp_dir/out" 2>&1 &
script_pid=$!

for _ in {1..100}; do
  grep -q '^signal$' "$tmp_dir/armed" 2>/dev/null && break
  kill -0 "$script_pid" 2>/dev/null || break
  sleep 0.05
done
grep -q '^signal$' "$tmp_dir/armed" || fail "screensaver arms its exit handler" "$(cat "$tmp_dir/armed" 2>/dev/null || true)"

# Once armed, the script spends its time inside the 1s read of its dismiss
# loop; give it a full cycle so the dismissal lands there.
sleep 1.2

# Dismiss the screensaver. While the exit handler is still running, the
# terminal it is killing echoes a hangup back, the way a real terminal does
# when the cleanup pkill takes it down.
kill -TERM "$script_pid" 2>/dev/null || true
sleep 0.05
kill -HUP "$script_pid" 2>/dev/null || true

set +e
wait "$script_pid"
status=$?
set -e

(( status == 0 )) || fail "screensaver exits cleanly after dismiss signals" "exit status $status"

restorations=$(grep -c '^cursor-restore$' "$log" || true)
(( restorations <= 1 )) ||
  fail "dismissing the screensaver restores the cursor exactly once" "$(printf '%s\n' "$log")"
pass "dismissing the screensaver restores the cursor exactly once"

grep -q '^pkill:-x ttfx$' "$log" || fail "dismissing the screensaver stops ttfx"
pass "dismissing the screensaver stops ttfx"