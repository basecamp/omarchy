#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

status=0

verify_core_packages() {
  local package
  local -a missing=()

  while IFS= read -r package; do
    [[ -z $package || $package == \#* ]] && continue
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
  done <"$OMARCHY_PATH/install/omarchy-base.packages"

  (( ${#missing[@]} == 0 )) || fail "all Omarchy core packages are installed" "missing packages: ${missing[*]}"
  pass "all Omarchy core packages are installed (${#missing[@]} missing)"
}

verify_defaults() {
  [[ $(omarchy-default-browser) == "chromium" ]] || fail "Chromium is the default browser"
  pass "Chromium is the default browser"

  [[ $(omarchy-default-terminal) == "foot" ]] || fail "Foot is the default terminal"
  pass "Foot is the default terminal"

  [[ $(omarchy-default-editor) == "nvim" ]] || fail "Neovim is the default editor"
  pass "Neovim is the default editor"

  [[ $(omarchy-theme-current) != "Unknown" ]] || fail "a current theme is configured"
  pass "a current theme is configured"

  [[ $(omarchy-theme-bg-current) != "Unknown" ]] || fail "a current background is configured"
  pass "a current background is configured"

  [[ -n $(omarchy-font-current) ]] || fail "a monospace font is configured"
  pass "a monospace font is configured"

  [[ $(xdg-mime query default x-scheme-handler/http) == "chromium.desktop" ]] || fail "HTTP MIME handling uses Chromium"
  [[ $(xdg-mime query default inode/directory) == "org.gnome.Nautilus.desktop" ]] || fail "directory MIME handling uses Nautilus"
  pass "desktop MIME handlers are configured"
}

verify_services() {
  local unit

  for unit in \
    avahi-daemon.service cups.service cups-browsed.service docker.socket \
    NetworkManager.service power-profiles-daemon.service sddm.service \
    systemd-resolved.service ufw.service; do
    systemctl is-enabled --quiet "$unit" || fail "core system services are enabled" "$unit is not enabled"
  done
  pass "core system services are enabled"

  for unit in NetworkManager.service systemd-resolved.service ufw.service; do
    systemctl is-active --quiet "$unit" || fail "critical system services are running" "$unit is not active"
  done
  pass "critical system services are running"

  systemctl --user is-active --quiet pipewire.service pipewire-pulse.service wireplumber.service ||
    fail "user audio services are running"
  pass "user audio services are running"
}

verify_printing_security() {
  local cups_browsed_pid lpinfo_output printer_name printer_process printer_tmp

  ! pacman -Q cups-pdf >/dev/null 2>&1 || fail "CUPS-PDF is absent"
  pass "the root CUPS-PDF backend is not installed"

  getent passwd cups-browsed >/dev/null || fail "the cups-browsed service account exists"
  [[ $(systemctl show -P User cups-browsed.service) == "cups-browsed" ]] ||
    fail "cups-browsed runs as its service account"
  [[ $(systemctl show -P Group cups-browsed.service) == "cups-browsed" ]] ||
    fail "cups-browsed runs as its service group"
  systemctl is-active --quiet cups-browsed.service || fail "cups-browsed is running"

  cups_browsed_pid=$(systemctl show -P MainPID cups-browsed.service)
  [[ -r /proc/$cups_browsed_pid/status ]] || fail "cups-browsed has a readable process status"
  [[ $(awk '/^Uid:/{print $2}' "/proc/$cups_browsed_pid/status") != 0 ]] ||
    fail "cups-browsed does not run with root UID"
  [[ $(awk '/^CapEff:/{print $2}' "/proc/$cups_browsed_pid/status") == "0000000000000000" ]] ||
    fail "cups-browsed has no effective Linux capabilities"

  [[ $(stat -c '%a %U:%G' /var/cache/cups-browsed) == "750 cups-browsed:cups-browsed" ]] ||
    fail "cups-browsed has an isolated cache" "$(stat -c '%a %U:%G' /var/cache/cups-browsed)"
  [[ " $(id -nG cups-browsed) " != *" cups "* ]] ||
    fail "cups-browsed is separate from the print-filter group"

  if lpinfo_output=$(LC_ALL=C timeout 10 lpinfo -v </dev/null 2>&1); then
    fail "the desktop user cannot administer CUPS without authentication"
  elif [[ $lpinfo_output != *"Forbidden"* ]]; then
    fail "CUPS explicitly denies unauthenticated desktop administration" "$lpinfo_output"
  fi

  pass "CUPS discovery is isolated from root, filters, and passwordless desktop administration"

  # A live driverless printer proves the non-root daemon can still discover and
  # create queues without the CAP_NET_BIND_SERVICE Ubuntu carries downstream.
  printer_name="OmarchyAcceptancePrinter"
  printer_tmp=$(mktemp -d)
  printf '#!/bin/bash\nexit 0\n' >"$printer_tmp/command"
  chmod 0700 "$printer_tmp/command"
  mkdir -m 0700 "$printer_tmp/spool"

  ippeveprinter -p 18631 -d "$printer_tmp/spool" -c "$printer_tmp/command" "$printer_name" \
    >"$printer_tmp/ippeveprinter.log" 2>&1 &
  printer_process=$!

  printing_test_cleanup() {
    kill "$printer_process" >/dev/null 2>&1 || true
    wait "$printer_process" >/dev/null 2>&1 || true
    rm -rf "$printer_tmp"
  }
  trap printing_test_cleanup EXIT

  for _ in {1..30}; do
    lpstat -v "$printer_name" 2>/dev/null | grep -q "implicitclass://$printer_name/" && break
    sleep 1
  done

  lpstat -v "$printer_name" 2>/dev/null | grep -q "implicitclass://$printer_name/" ||
    fail "non-root cups-browsed discovers a driverless IPP printer" "$(<"$printer_tmp/ippeveprinter.log")"

  printing_test_cleanup
  trap - EXIT

  pass "non-root cups-browsed still creates driverless IPP queues without capabilities"
}

verify_runtime_tools() {
  # Docker access is intentionally NOT granted to the desktop user: the docker
  # group is root-equivalent, so a rogue process running as the user could
  # otherwise `docker run -v /:/host` its way to passwordless root. The daemon is
  # still enabled (docker.socket, checked in verify_services) and reached through
  # a polkit/sudo prompt; opting into sudoless Docker is a separate, warned step.
  command -v docker >/dev/null 2>&1 || fail "Docker CLI is installed"
  ! id -nG | grep -qw docker || fail "desktop user must not be in the docker group"
  # The group name being absent is not sufficient — a world-writable socket or an
  # ACL would still hand the user the root daemon. Prove it is actually
  # unreachable without elevation.
  if timeout 10 docker info >/dev/null 2>&1; then
    fail "desktop user must not reach the Docker daemon without elevation"
  fi
  pass "Docker is installed but unreachable by the desktop user without elevation"

  nvim --headless '+qa' >/dev/null 2>&1 || fail "Neovim starts headlessly"
  pass "Neovim starts headlessly"

  timeout 10 fastfetch --pipe false >/dev/null 2>&1 || fail "Fastfetch can read system information"
  pass "Fastfetch can read system information"

  git --version >/dev/null || fail "Git is installed and runnable"
  tmux -V >/dev/null || fail "Tmux is installed and runnable"
  mise --version >/dev/null || fail "Mise is installed and runnable"
  pass "core terminal tools are runnable"
}

verify_user_setup() {
  local directory

  for directory in DESKTOP DOCUMENTS DOWNLOAD PICTURES; do
    [[ -d $(xdg-user-dir "$directory") ]] || fail "XDG user directories exist" "$directory is missing"
  done
  pass "XDG user directories exist"

  [[ -e $HOME/.local/state/omarchy/current/theme ]] || fail "current theme state exists"
  [[ -e $HOME/.local/state/omarchy/current/background ]] || fail "current background state exists"
  [[ -s $HOME/.config/omarchy/shell.json ]] || fail "shell configuration exists"
  jq empty "$HOME/.config/omarchy/shell.json" || fail "shell configuration is valid JSON"
  pass "Omarchy user state and shell configuration exist"
}

for check in verify_core_packages verify_defaults verify_services verify_printing_security verify_runtime_tools verify_user_setup; do
  if ! ("$check"); then
    status=1
  fi
done

exit $status
