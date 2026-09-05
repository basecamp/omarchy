#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
export OMARCHY_PATH="$ROOT"

(
  source "$ROOT/bin/omarchy-lab-vm"
  KEY="$test_tmp/new-home/.ssh/omarchy-lab"
  ensure_ssh_key
  [[ -s $KEY && -s $KEY.pub ]] || fail "fresh-account key generation"
  [[ $(stat -c %a "$(dirname "$KEY")") == "700" ]] || fail "SSH directory permissions"
  [[ $(stat -c %a "$KEY") == "600" ]] || fail "SSH key permissions"
)
pass "first install creates a private SSH directory"

(
  source "$ROOT/bin/omarchy-lab-gold"
  is_tty() { return 1; }
  launch_lifecycle_terminal() { printf '%s\n' "$*" >>"$test_tmp/terminal"; }
  sudo() { fail "graphical lifecycle must hand off before sudo"; }
  have_domain() { fail "graphical lifecycle must hand off before domain access"; }
  require_lab() { fail "graphical rebuild must hand off before domain access"; }
  reset_lab
  rebuild_gold --yes --json
  promote_gold --yes --json
  [[ $(wc -l <"$test_tmp/terminal") == 3 ]] || fail "all privileged lifecycle actions open terminals"
)
(
  source "$ROOT/bin/omarchy-lab-gold"
  is_tty() { return 0; }
  sudo() { return 1; }
  require_lab() { :; }
  have_domain() { fail "reset must authenticate first"; }
  preserve_checkpoints() { fail "rebuild must authenticate first"; }
  remove_lab() { fail "failed authentication must preserve data"; }
  if reset_lab; then fail "reset accepted failed authentication"; fi
  if rebuild_gold --yes; then fail "rebuild accepted failed authentication"; fi
  if promote_gold --yes; then fail "promotion accepted failed authentication"; fi
)
pass "graphical lifecycle hands off and failed authentication cannot delete data"

(
  source "$ROOT/bin/omarchy-lab-network"
  require_lab() { :; }
  domain_running() { return 1; }
  interface_source() { echo default; }
  run_virsh() {
    case $1 in
    domiflist) printf 'vnet0 network default virtio 52:54:00:12:34:56\n' ;;
    domif-getlink) printf '52:54:00:12:34:56 up\n' ;;
    *) return 2 ;;
    esac
    # Simulate output arriving after a consumer has already read its match.
    sleep 0.05
    printf '%65536s\n' trailing-output
  }
  [[ $(lab_mac) == "52:54:00:12:34:56" ]] || fail "NIC probe lost its first match"
  network_status_json >"$test_tmp/network-drain.json"
  jq -e '.mode == "nat" and .link == "up"' "$test_tmp/network-drain.json" >/dev/null || fail "link probe did not consume all output"
  run_virsh() { return 7; }
  if lab_mac; then fail "failed virsh must not become successful empty output"; fi
)
pass "network probes drain delayed output without SIGPIPE and preserve failures"

(
  source "$ROOT/bin/omarchy-lab-action"
  require_running_lab() { :; }
  session_lab() {
    [[ $1 == *'systemd-run --user --quiet --collect --property=Type=exec'* ]] || fail "terminal must be guest-service owned"
    [[ $1 == *'--setenv=WAYLAND_DISPLAY='* && $1 == *'--setenv=OMARCHY_PATH='* ]] || fail "terminal needs graphical checkout environment"
    [[ $1 != *'--wait'* ]] || fail "terminal must not wait for application exit"
    [[ $1 == *'--property=ExitType=cgroup'* ]] || fail "forked launcher children must survive parent exit"
    return 0
  }
  run_action terminal
  session_lab() { return 9; }
  if run_action terminal; then fail "terminal launch failure must propagate"; fi
)
pass "terminal launch is detached from panel lifetime and propagates launch errors"

(
  source "$ROOT/bin/omarchy-lab-vm"
  STATE_DIR="$test_tmp/reset-state"
  mkdir -p "$STATE_DIR"
  run_virsh() {
    case $1 in
    net-info) printf '%s' "$2" >"$test_tmp/reset-network" ;;
    dumpxml) printf "<interface type='network'>\n<source network='omarchy-lab-isolated'/>\n<link state='down'/>\n</interface>\n" ;;
    update-device) cat >"$test_tmp/reset-interface" ;;
    *) fail "unexpected reset network operation: $*" ;;
    esac
  }
  restore_gold_network
  rg -q "source network='default'" "$test_tmp/reset-interface" || fail "original gold restores NAT"
  rg -q "link state='up'" "$test_tmp/reset-interface" || fail "reset reconnects offline interface"
  printf '{"networkSource":"omarchy-lab-isolated"}\n' >"$STATE_DIR/gold.json"
  restore_gold_network
  rg -q "source network='omarchy-lab-isolated'" "$test_tmp/reset-interface" || fail "promoted gold retains its own network"
)
pass "reset reconciles original and promoted gold network configurations"

(
  source "$ROOT/bin/omarchy-lab-common"
  CHECKPOINT_DIR="$test_tmp/checkpoints"
  mkdir -p "$CHECKPOINT_DIR"
  run_as_root() {
    if [[ $1 == "chown" ]]; then return 0; else command "$@"; fi
  }
  qemu-img create -q -f qcow2 "$test_tmp/base.qcow2" 16M
  qemu-io -c 'write -P 0x11 0 4096' "$test_tmp/base.qcow2" >/dev/null
  qemu-img create -q -f qcow2 -F qcow2 -b "$test_tmp/base.qcow2" "$CHECKPOINT_DIR/saved.qcow2"
  preserve_checkpoints
  qemu-io -c 'write -P 0x22 0 4096' "$test_tmp/base.qcow2" >/dev/null
  preserve_checkpoints
  qemu-io -c 'write -P 0x33 0 4096' "$test_tmp/base.qcow2" >/dev/null
  qemu-io -c 'read -P 0x11 0 4096' "$CHECKPOINT_DIR/saved.qcow2" >/dev/null
  qemu-img info --output=json "$CHECKPOINT_DIR/saved.qcow2" | jq -e 'has("backing-filename") | not' >/dev/null
  qemu-img create -q -f qcow2 -F qcow2 -b "$test_tmp/base.qcow2" "$CHECKPOINT_DIR/failure.qcow2"
  before=$(sha256sum "$CHECKPOINT_DIR/failure.qcow2")
  run_as_root() { return 1; }
  if preserve_checkpoints; then fail "failed conversion accepted"; fi
  [[ $(sha256sum "$CHECKPOINT_DIR/failure.qcow2") == "$before" ]] || fail "failed conversion replaced checkpoint"
)
pass "legacy checkpoints preserve bytes across repeated gold replacement and conversion failure"

(
  source "$ROOT/bin/omarchy-lab-checkpoint"
  CHECKPOINT_DIR="$test_tmp/new-checkpoints"
  require_lab() { :; }
  find_pool() { echo test; }
  domain_running() { return 1; }
  run_as_root() {
    if [[ $1 == "chown" ]]; then return 0; else command "$@"; fi
  }
  qemu-img create -q -f qcow2 -F qcow2 -b "$test_tmp/base.qcow2" "$test_tmp/current.qcow2"
  run_virsh() {
    [[ $1 == "vol-download" ]] || fail "unexpected checkpoint operation: $*"
    cp "$test_tmp/current.qcow2" "$3"
  }
  create_checkpoint independent --json >/dev/null
  qemu-img info --output=json "$CHECKPOINT_DIR/independent.qcow2" | jq -e 'has("backing-filename") | not' >/dev/null
  qemu-io -c 'write -P 0x44 0 4096' "$test_tmp/base.qcow2" >/dev/null
  qemu-io -c 'read -P 0x33 0 4096' "$CHECKPOINT_DIR/independent.qcow2" >/dev/null
)
pass "new checkpoints are self-contained when created"

(
  source "$ROOT/bin/omarchy-lab-gold"
  is_tty() { return 0; }
  sudo() { return 0; }
  require_lab() { :; }
  preserve_checkpoints() { return 1; }
  guest_user() { fail "rebuild must preserve checkpoints before proceeding"; }
  remove_lab() { fail "rebuild cannot delete gold after failed preservation"; }
  if rebuild_gold --yes; then fail "rebuild accepted failed checkpoint preservation"; fi
)
pass "rebuild fails before removal if checkpoint preservation fails"

branch_repo="$test_tmp/repo"
mkdir -p "$branch_repo"
git -C "$branch_repo" init -qb main
git -C "$branch_repo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm Initial
for failure in copy link guest-metadata host-metadata reboot; do
  (
    source "$ROOT/bin/omarchy-lab-checkout"
    DEPLOYMENT_FILE="$test_tmp/deployment-$failure.json"
    require_running_lab() { :; }
    guest_user() { echo lab; }
    push_lab() { [[ $failure != "copy" ]]; }
    lab_ssh() {
      printf '%s\n' "$*" >>"$test_tmp/ssh-$failure"
      if [[ $1 == /usr/bin/omarchy-dev-link* ]]; then
        [[ $failure != "link" ]]
      else
        [[ $failure != "guest-metadata" ]]
      fi
    }
    write_private_json() { [[ $failure != "host-metadata" ]]; }
    lab_reboot() { printf reboot >"$test_tmp/reboot-$failure"; return 1; }
    wait_ssh() { fail "failed reboot must not wait"; }
    if deploy_branch main "$branch_repo" --json >"$test_tmp/output-$failure"; then
      fail "deployment swallowed $failure failure"
    fi
    [[ ! -s $test_tmp/output-$failure ]] || fail "failed deployment printed success"
    if [[ $failure != "reboot" ]]; then
      [[ ! -e $test_tmp/reboot-$failure ]] || fail "failed deployment rebooted"
    fi
    if [[ $failure == "copy" ]]; then
      [[ ! -e $test_tmp/ssh-$failure ]] || fail "copy failure continued to guest writes"
    fi
  )
done
pass "branch deployment propagates copy, dev-link, metadata, and reboot failures"

(
  source "$ROOT/bin/omarchy-lab-health"
  guest_ip() { echo 192.0.2.1; }
  guest_user() { echo lab; }
  session_lab() { fail "health must not use lifecycle session helper"; }
  wait_ssh() { fail "health must not wait/start"; }
  timeout() {
    [[ $1 == "--kill-after=1" && $2 == 8 && $3 == "ssh" ]] || fail "health probe must bound remote execution"
    return 124
  }
  if guest_health_json; then fail "unavailable health accepted"; fi
)
pass "health polling uses one bounded read-only SSH probe"

for source_network in default omarchy-lab-isolated; do
  (
    source "$ROOT/bin/omarchy-lab-network"
    link=down
    running=true
    target=default
    [[ $source_network == "default" ]] && target=omarchy-lab-isolated
    lab_mac() { echo 52:54:00:00:00:01; }
    domain_running() { $running; }
    lab_ssh() { [[ $link == "up" ]]; }
    prepare_guest_network() {
      [[ $link == "up" && $1 == "$target" ]] || fail "preparation needs old network connectivity"
      printf prepared >"$test_tmp/network-prepared-$target"
    }
    stop_guest() { running=false; }
    wait_ssh() { :; }
    run_virsh() {
      case $1 in
      domif-setlink) link=$4 ;;
      dumpxml) printf "<interface type='network'>\n<source network='%s'/>\n</interface>\n" "$source_network" ;;
      update-device)
        [[ -f $test_tmp/network-prepared-$target ]] || fail "source switched without preparation"
        cat >"$test_tmp/network-interface-$target"
        ;;
      start) running=true ;;
      *) fail "unexpected network operation: $*" ;;
      esac
    }
    switch_source "$target"
    rg -q "source network='$target'" "$test_tmp/network-interface-$target" || fail "source not switched"
    running=false
    run_virsh() { fail "stopped-source change must not mutate domain"; }
    if switch_source "$target"; then fail "stopped-source change accepted"; fi
  )
done
pass "offline source transitions reconnect first and stopped transitions are rejected"

(
  source "$ROOT/bin/omarchy-lab-capture"
  OMARCHY_PATH="$test_tmp/capture-root"
  ARTIFACT_DIR="$test_tmp/capture-artifacts"
  mkdir -p "$OMARCHY_PATH/bin"
  printf '#!/bin/bash\nexit 0\n' >"$OMARCHY_PATH/bin/omarchy-lab-viewer"
  chmod +x "$OMARCHY_PATH/bin/omarchy-lab-viewer"
  require_running_lab() { :; }
  omarchy-shell() { :; }
  hyprctl() { printf '{"class":"virt-viewer","title":"omarchy-lab"}\n'; }
  require_viewer_region() { echo 5120x1440+0+0; }
  send_key_lab() { :; }
  gpu-screen-recorder() {
    [[ $* == *"-s 4096x4096"* ]] || fail "recording must cap H.264 output size"
    return 1
  }
  if capture_recording 1 --json >"$test_tmp/failed-recording.json" 2>"$test_tmp/failed-recording.log"; then
    fail "recorder startup failure returned success"
  fi
  [[ -z $(trap -p EXIT) ]] || fail "failed recorder left a trap referencing dead local state"
  [[ ! -s $test_tmp/failed-recording.json ]] || fail "failed recording returned success JSON"
)
pass "oversized viewer capture is bounded and recorder startup failures clean up"

run_node_test <<'JS'
const fs = require('fs')
const panel = fs.readFileSync(path.join(root, 'shell/plugins/panels/lab/Panel.qml'), 'utf8')
const record = panel.match(/function recordViewer\(\) \{([\s\S]*?)\n  \}/)[1]
assert(record.indexOf('close()') < record.indexOf('runCommand('), 'recording closes the panel before launching capture')
const capture = fs.readFileSync(path.join(root, 'bin/omarchy-lab-capture'), 'utf8')
assert(capture.indexOf('omarchy-shell shell hide omarchy.lab') < capture.indexOf('gpu-screen-recorder -w'), 'CLI recording hides the panel before capture too')
JS
