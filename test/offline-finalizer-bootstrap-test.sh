#!/usr/bin/env bash
# Ensure the offline/chroot finalizer reaches target-side scripts with no
# controlling tty. This specifically protects against finalize.sh sourcing the
# interactive helper bundle (presentation/errors) before the parent can capture
# a useful failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/install/helpers" \
  "$TMP/install/packaging" \
  "$TMP/install/config" \
  "$TMP/install/login" \
  "$TMP/install/post-install" \
  "$TMP/omarchy/migrations" \
  "$TMP/home"

cp "$ROOT/install/helpers/mode.sh" "$TMP/install/helpers/"
cp "$ROOT/install/helpers/chroot.sh" "$TMP/install/helpers/"
cp "$ROOT/install/helpers/logging.sh" "$TMP/install/helpers/"

cat >"$TMP/install/packaging/all.sh" <<'SCRIPT'
run_logged "$OMARCHY_INSTALL/packaging/marker.sh"
SCRIPT

cat >"$TMP/install/packaging/marker.sh" <<'SCRIPT'
echo packaging-marker
SCRIPT

cat >"$TMP/install/config/all.sh" <<'SCRIPT'
echo config-marker >>"$OMARCHY_INSTALL_LOG_FILE"
SCRIPT

cat >"$TMP/install/login/all.sh" <<'SCRIPT'
install_mode_is offline
echo login-marker >>"$OMARCHY_INSTALL_LOG_FILE"
SCRIPT

cat >"$TMP/install/post-install/all.sh" <<'SCRIPT'
stop_install_log
touch "$HOME/finalizer-completed"
SCRIPT

if grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*helpers/all\.sh' "$ROOT/finalize.sh"; then
  echo "finalize.sh must not source helpers/all.sh" >&2
  exit 1
fi

output="$({
  setsid -w env \
    OMARCHY_INSTALL="$TMP/install" \
    OMARCHY_PATH="$TMP/omarchy" \
    OMARCHY_INSTALL_MODE=offline \
    OMARCHY_CHROOT_FINALIZER=1 \
    OMARCHY_INSTALL_LOG_FILE="$TMP/omarchy-install.log" \
    HOME="$TMP/home" \
    USER=ryan \
    bash "$ROOT/finalize.sh" </dev/null
} 2>&1)"

printf '%s\n' "$output"

if [[ ! -f "$TMP/home/finalizer-completed" ]]; then
  echo "expected finalizer completion marker" >&2
  exit 1
fi

if ! grep -q 'packaging-marker' "$TMP/omarchy-install.log"; then
  echo "expected run_logged script output in install log" >&2
  exit 1
fi

if ! grep -q 'login-marker' "$TMP/omarchy-install.log"; then
  echo "expected sourced target scripts to run" >&2
  exit 1
fi

if [[ $output == *$'\033[?25h'* ]]; then
  echo "offline finalizer leaked cursor escape" >&2
  exit 1
fi

if [[ $output == *'Inappropriate ioctl'* || $output == *'/dev/tty'* ]]; then
  echo "offline finalizer attempted tty access" >&2
  exit 1
fi

rm -f "$TMP/home/finalizer-completed" "$TMP/omarchy-install.log"
debug_output="$({
  setsid -w env \
    OMARCHY_INSTALL_DEBUG=1 \
    OMARCHY_INSTALL="$TMP/install" \
    OMARCHY_PATH="$TMP/omarchy" \
    OMARCHY_INSTALL_MODE=offline \
    OMARCHY_CHROOT_FINALIZER=1 \
    OMARCHY_INSTALL_LOG_FILE="$TMP/omarchy-install.log" \
    HOME="$TMP/home" \
    USER=ryan \
    bash "$ROOT/finalize.sh" </dev/null
} 2>&1)"

printf '%s\n' "$debug_output"

if [[ ! -f "$TMP/home/finalizer-completed" ]]; then
  echo "expected debug finalizer completion marker" >&2
  exit 1
fi

if ! grep -q '\[finalize-debug\] tracing enabled' "$TMP/omarchy-install.log"; then
  echo "expected finalize debug trace marker in install log" >&2
  exit 1
fi

if ! grep -q 'source .*/helpers/mode.sh' "$TMP/omarchy-install.log"; then
  echo "expected helper source trace in debug install log" >&2
  exit 1
fi

if ! grep -q 'packaging-marker' "$TMP/omarchy-install.log"; then
  echo "expected debug run_logged script output in install log" >&2
  exit 1
fi

if [[ $debug_output == *'Inappropriate ioctl'* || $debug_output == *'/dev/tty'* ]]; then
  echo "debug offline finalizer attempted tty access" >&2
  exit 1
fi

echo "offline finalizer bootstrap test passed"
