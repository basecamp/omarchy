#!/bin/bash
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
  "$TMP/install/user" \
  "$TMP/install/config" \
  "$TMP/install/login" \
  "$TMP/install/post-install" \
  "$TMP/omarchy/applications/icons" \
  "$TMP/omarchy/bin" \
  "$TMP/omarchy/config" \
  "$TMP/omarchy/default/alacritty" \
  "$TMP/omarchy/default/hypr/toggles" \
  "$TMP/omarchy/default/nautilus-python/extensions" \
  "$TMP/omarchy/default/omarchy-skill" \
  "$TMP/omarchy/migrations" \
  "$TMP/home"

cp "$ROOT/install/helpers/mode.sh" "$TMP/install/helpers/"
cp "$ROOT/install/helpers/chroot.sh" "$TMP/install/helpers/"
cp "$ROOT/install/helpers/logging.sh" "$TMP/install/helpers/"
ln -s "$TMP/install" "$TMP/omarchy/install"

cat >"$TMP/install/user/all.sh" <<'SCRIPT'
run_logged "$OMARCHY_INSTALL/packaging/marker.sh"
install_mode_is offline
echo user-marker >>"$OMARCHY_INSTALL_LOG_FILE"
stop_install_log
touch "$HOME/finalizer-completed"
SCRIPT

cat >"$TMP/install/packaging/marker.sh" <<'SCRIPT'
echo packaging-marker
SCRIPT

for script in icons webapps tuis npm; do
  cat >"$TMP/install/packaging/$script.sh" <<'SCRIPT'
:
SCRIPT
done

cat >"$TMP/install/post-install/finished.sh" <<'SCRIPT'
stop_install_log
touch "$HOME/finalizer-completed"
return 0 2>/dev/null || exit 0
SCRIPT

cat >"$TMP/omarchy/default/bashrc" <<'EOF'
# test bashrc
EOF
cat >"$TMP/omarchy/default/alacritty/Alacritty.desktop" <<'EOF'
[Desktop Entry]
Name=Alacritty
Type=Application
Exec=true
EOF
cat >"$TMP/omarchy/default/hypr/toggles/flags.lua" <<'EOF'
return {}
EOF
: >"$TMP/omarchy/default/nautilus-python/extensions/localsend.py"
: >"$TMP/omarchy/default/nautilus-python/extensions/transcode.py"
cat >"$TMP/omarchy/icon.txt" <<'EOF'
icon
EOF
cat >"$TMP/omarchy/logo.txt" <<'EOF'
logo
EOF
cat >"$TMP/omarchy/applications/test.desktop" <<'EOF'
[Desktop Entry]
Name=Test
Type=Application
Exec=true
EOF
: >"$TMP/omarchy/applications/icons/Test.png"

for cmd in gtk-update-icon-cache update-desktop-database xdg-mime xdg-settings xdg-user-dirs-update; do
  cat >"$TMP/omarchy/bin/$cmd" <<'SCRIPT'
#!/bin/bash
:
SCRIPT
  chmod +x "$TMP/omarchy/bin/$cmd"
done

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

if ! grep -q 'user-marker' "$TMP/omarchy-install.log"; then
  echo "expected sourced user scripts to run" >&2
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
