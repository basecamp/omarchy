#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
export OMARCHY_PATH="$ROOT"
source "$ROOT/bin/omarchy-lab-vm"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
STATE_DIR="$test_tmp/state"
mkdir -p "$test_tmp/db/sync"
pacman-conf() {
  case $1 in
    DBPath) echo "$test_tmp/db/" ;;
    --repo-list) printf '%s\n' core extra custom ;;
  esac
}
omarchy-pkg-add() { printf 'packages %s\n' "$*" >>"$test_tmp/calls"; }
omarchy-update() { echo "update $*" >>"$test_tmp/calls"; }

ensure_install_packages
[[ $(head -1 "$test_tmp/calls") == 'update -y' ]] || fail 'fresh database must update before dependencies'
rg -q 'packages .*qemu-full .*openbsd-netcat' "$test_tmp/calls" || fail 'missing required packages'
[[ ! -f $STATE_DIR/package-update-required ]] || fail 'successful update marker leaked'
pass 'missing enabled repositories trigger a full Omarchy update before installing dependencies'

for repository in core extra custom; do printf db >"$test_tmp/db/sync/$repository.db"; done
: >"$test_tmp/calls"
ensure_install_packages
[[ $(wc -l <"$test_tmp/calls") == 1 ]] || fail 'existing repositories unnecessarily upgraded the host'
pass 'populated repositories use the normal package helper without a system upgrade'

(
  : >"$test_tmp/db/sync/custom.db"
  : >"$test_tmp/calls"
  omarchy-update() { printf db >"$test_tmp/db/sync/custom.db"; return 9; }
  if ensure_install_packages; then fail 'failed update reported success'; fi
  [[ ! -s $test_tmp/calls && -f $STATE_DIR/package-update-required ]] || fail 'failed update installed packages or lost retry state'
)
: >"$test_tmp/calls"
ensure_install_packages
[[ $(head -1 "$test_tmp/calls") == 'update -y' ]] || fail 'retry skipped unfinished update after databases appeared'
pass 'update failure blocks dependencies and retries the full update even after databases were downloaded'
(
  omarchy-pkg-add() { return 8; }
  if ensure_install_packages; then fail 'package failure reported success'; fi
)
pass 'dependency failure is propagated'

(
  lab_ssh_quiet() { return 0; }
  configure_guest_sudo() { fail 'healthy guest must not rewrite sudo policy'; }
  install_guest_display_resize() { fail 'healthy guest must not reinstall or update'; }
  lab_ssh() {
    [[ $1 == *'sudo -n systemctl start spice-vdagentd.socket'* ]] || fail 'SPICE socket not started'
    [[ $1 == *'systemctl --user start spice-vdagent.service omarchy-lab-display-resize.service'* ]] || fail 'both guest session services must start without reboot'
  }
  ensure_guest_display_resize
)
pass 'healthy display integration starts services without reinstalling packages'

(
  lab_ssh_quiet() { return 1; }
  guest_user() { echo lab; }
  configure_guest_sudo() { echo sudo >>"$test_tmp/display-calls"; }
  install_guest_display_resize() { echo install >>"$test_tmp/display-calls"; }
  lab_ssh() { echo start >>"$test_tmp/display-calls"; }
  ensure_guest_display_resize
  [[ $(paste -sd ' ' "$test_tmp/display-calls") == 'sudo install start' ]] || fail 'legacy guest repair order'
  install_guest_display_resize() { return 8; }
  lab_ssh() { fail 'failed repair must not continue'; }
  if ensure_guest_display_resize; then fail 'failed display installation accepted'; fi
  configure_guest_sudo() { return 9; }
  install_guest_display_resize() { fail 'failed sudo must not install'; }
  if ensure_guest_display_resize; then fail 'failed guest authentication accepted'; fi
)
pass 'legacy gold display tools are repaired with explicit failure propagation'

(
  lab_ssh_quiet() { return 1; }
  lab_ssh() { fail 'noninteractive repair must not ask for a password'; }
  if configure_guest_sudo lab; then fail 'guest without passwordless sudo accepted'; fi
)
(
  lab_ssh() { return 7; }
  lab_ssh_quiet() { fail 'failed asset upload must stop provisioning'; }
  if install_guest_display_resize; then fail 'failed asset upload accepted'; fi
)
pass 'display repair cannot hang on a sudo prompt or swallow asset upload failures'

(
  is_tty() { return 0; }
  sudo() { :; }
  have_domain() { return 0; }
  find_pool() { echo test-pool; }
  domain_running() { return 1; }
  restore_gold_network() { :; }
  run_virsh() { :; }
  CONFIG_FILE="$test_tmp/no-config"
  KNOWN_HOSTS="$test_tmp/no-known-hosts"
  wait_ssh() { echo ssh >>"$test_tmp/reset-calls"; }
  wait_hypr() { echo hypr >>"$test_tmp/reset-calls"; }
  ensure_guest_display_resize() { echo repair >>"$test_tmp/reset-calls"; }
  guest_ip() { echo 192.0.2.2; }
  reset_lab >"$test_tmp/reset-output"
  [[ $(paste -sd ' ' "$test_tmp/reset-calls") == 'ssh hypr repair' ]] || fail 'reset must repair the restored guest'
  ensure_guest_display_resize() { return 8; }
  if reset_lab >"$test_tmp/reset-output"; then fail 'reset ignored failed display repair'; fi
  [[ ! -s $test_tmp/reset-output ]] || fail 'reset falsely reported success'
)
pass 'reset repairs integration on the restored overlay and cannot report a failed repair as success'

routes='[{"dst":"default","dev":"eth0"},{"dst":"192.168.122.0/24","dev":"eth0"},{"dst":"192.168.124.0/23","dev":"vpn0"}]'
if lab_subnet_available 192.168.122.1 "$routes"; then fail 'nested subnet overlap accepted'; fi
if lab_subnet_available 192.168.125.1 "$routes"; then fail 'larger VPN route overlap accepted'; fi
lab_subnet_available 192.168.126.1 "$routes" || fail 'unused subnet rejected'
lab_subnet_available 192.168.124.1 '[{"dst":"192.168.124.0/24","dev":"virbr0"}]' || fail 'own bridge considered a conflict'
pass 'subnet selection handles nested networks, larger CIDRs, and its own bridge'

network_xml="<network><name>default</name>
<ip address='192.168.122.1' netmask='255.255.255.0'>
<dhcp><range start='192.168.122.2' end='192.168.122.254'/></dhcp></ip></network>"
active=false
used=false
fixture_routes=$routes
ip() { printf '%s\n' "$fixture_routes"; }
run_virsh() {
  case $1 in
    net-dumpxml) printf '%s\n' "$network_xml" ;;
    net-list) if $active; then echo default; fi ;;
    list) if $used; then echo other-vm; fi ;;
    dumpxml) echo "<domain><interface><source network='default'/></interface></domain>" ;;
    net-define) network_xml=$(cat); printf '%s\n' "$network_xml" >"$test_tmp/defined.xml" ;;
    *) fail "unexpected virsh action $*" ;;
  esac
}
(
  active=true
  if ensure_default_network; then fail 'active network renumbered'; fi
  [[ ! -e $test_tmp/defined.xml ]] || fail 'active network changed'
)
(
  used=true
  if ensure_default_network; then fail 'existing VM network renumbered'; fi
  [[ ! -e $test_tmp/defined.xml ]] || fail 'existing VM network changed'
)
ensure_default_network
[[ $LIBVIRT_NET == '192.168.126.1' ]] || fail 'wrong non-overlapping gateway'
rg -q '192.168.126.254' "$test_tmp/defined.xml" || fail 'DHCP range not moved with gateway'
rg -q '192.168.122.1' "$STATE_DIR/default-network-before-lab.xml" || fail 'original definition not preserved'
pass 'only an unused conflicting default network is renumbered, with a backup and matching DHCP range'

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(path.join(root, 'bin/omarchy-lab-vm'), 'utf8')
const reset = source.match(/reset_lab\(\) \{[^]*?\n}/)[0]
assert(reset.indexOf('ensure_guest_display_resize || return 1') > reset.indexOf('wait_ssh'), 'reset repairs legacy gold integration after SSH comes up')
const aspect = source.match(/resize_viewer_aspect\(\) \{[^]*?\n}/)[0]
assert(aspect.indexOf('ensure_guest_display_resize || return 1') < aspect.indexOf('geometry=$(wait_viewer_geometry)'), 'aspect repairs guest integration before negotiating viewer geometry')
assert(source.includes('LIBVIRT_NET=$(nat_gateway) || return 1'), 'guest SSH firewall uses the actual NAT gateway')
assert(source.includes('HYPERVISOR_PACKAGES=(spice-vdagent)') && source.includes('$(declare -f ensure_install_packages)'), 'first-boot guest dependencies use the same database recovery as the installer')
assert(source.includes('Defaults:%s verifypw=any'), 'passwordless Lab account can validate sudo for unattended guest updates')
assert(!source.match(/enable_lab_controls\(\) \{[^]*?\n}/)[0].includes('rescanPlugins'), 'finishing setup does not reload unrelated shell plugins')
JS
