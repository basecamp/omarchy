#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const commands = ['action', 'capture', 'checkout', 'checkpoint', 'common', 'gold', 'health', 'network', 'resource', 'scenario', 'transfer']
for (const name of commands) {
  const file = path.join(root, 'bin', `omarchy-lab-${name}`)
  const source = fs.readFileSync(file, 'utf8')
  assert(source.startsWith('#!/bin/bash\n'), `${name} uses the repository bash shebang`)
  assert(source.includes('set -euo pipefail'), `${name} enables strict shell behavior`)
  assert(source.includes('# omarchy:summary='), `${name} has command metadata`)
}

for (const name of ['checkpoint', 'gold']) {
  const source = fs.readFileSync(path.join(root, 'bin', `omarchy-lab-${name}`), 'utf8')
  assert(source.includes('confirm_destructive'), `${name} routes destructive operations through confirmation`)
  assert(source.includes('--yes'), `${name} has an explicit non-interactive confirmation flag`)
}

const scenario = fs.readFileSync(path.join(root, 'bin/omarchy-lab-scenario'), 'utf8')
assert(scenario.includes('all(.command[]; type == "string")'), 'scenario steps are argument arrays')
assert(!scenario.includes('eval '), 'scenario runner never evaluates shell strings')

const network = fs.readFileSync(path.join(root, 'bin/omarchy-lab-network'), 'utf8')
assert(network.includes('ipv4.never-default yes'), 'isolated mode gives the guest no default route')
assert(network.includes('update-device') && !network.includes('detach-interface'), 'network switching preserves the guest NIC identity')

const resource = fs.readFileSync(path.join(root, 'bin/omarchy-lab-resource'), 'utf8')
assert(resource.includes('Power-cycling the Lab'), 'resource changes use a full VM cycle')

const transfer = fs.readFileSync(path.join(root, 'bin/omarchy-lab-transfer'), 'utf8')
assert(transfer.includes('systemd-run --user') && transfer.includes('wl-copy --foreground'), 'guest clipboard ownership survives the SSH session')
JS

test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_LAB_DATA_DIR="$test_tmp/state"
export OMARCHY_LAB_CHECKPOINT_DIR="$test_tmp/state/checkpoints"
export OMARCHY_LAB_ARTIFACT_DIR="$test_tmp/state/artifacts"
export OMARCHY_LAB_SCENARIO_DIR="$test_tmp/config/scenarios"
mkdir -p "$HOME" "$OMARCHY_LAB_SCENARIO_DIR"

(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-resource"
  RESOURCE_FILE="$test_tmp/resource-profile.json"
  resource_calls="$test_tmp/resource-calls"
  resource_status_json() {
    printf '%s\n' '{"profile":"performance","running":false,"cpus":{"maximum":8,"configured":8,"live":8},"memory":{"maximumBytes":17179869184,"configuredBytes":17179869184},"host":{"cpus":32,"memoryBytes":132070244352,"balancedCpus":4,"balancedMemoryBytes":8589934592,"performanceCpus":8,"performanceMemoryBytes":17179869184,"fullCpus":16,"fullMemoryBytes":34359738368,"safeCpus":24,"safeMemoryBytes":98784247808}}'
  }
  require_lab() { :; }
  domain_running() { return 1; }
  run_virsh() { printf '%s\n' "$*" >>"$resource_calls"; }

  set_resource_profile performance --json >/dev/null
  rg -qx 'setvcpus omarchy-lab 8 --config' "$resource_calls" || fail "performance applies its workload-based CPU count"
  rg -qx 'setmem omarchy-lab 16777216 --config' "$resource_calls" || fail "performance applies its workload-based memory"
  jq -e '.profile == "performance" and .cpus == 8 and .memoryGiB == 16' "$RESOURCE_FILE" >/dev/null || fail "performance persists its workload-based allocation"

  : >"$resource_calls"
  set_resource_profile full --json >/dev/null
  rg -qx 'setvcpus omarchy-lab 16 --maximum --config' "$resource_calls" || fail "full expands the VM CPU ceiling"
  rg -qx 'setmaxmem omarchy-lab 33554432 --config' "$resource_calls" || fail "full expands the VM memory ceiling"
  rg -qx 'setvcpus omarchy-lab 16 --config' "$resource_calls" || fail "full applies its workload-based CPU count"
  rg -qx 'setmem omarchy-lab 33554432 --config' "$resource_calls" || fail "full applies its workload-based memory"
  jq -e '.profile == "full" and .cpus == 16 and .memoryGiB == 32' "$RESOURCE_FILE" >/dev/null || fail "full persists its workload-based allocation"

  if set_resource_profile custom 25 64 --json >/dev/null 2>&1; then
    fail "custom resources cannot consume the host reserve"
  fi
)
pass "resource profiles stay workload-based and expand the VM ceiling safely"

(
  source "$ROOT/bin/omarchy-lab-resource"
  RESOURCE_FILE="$test_tmp/resource-resizing.json"
  mock_max_cpus=16 mock_cpus=8 mock_max_kib=67108864 mock_kib=16777216
  mock_running=true mock_stops=0 mock_starts=0
  require_lab() { :; }
  domain_running() { $mock_running; }
  stop_guest() { mock_running=false; ((++mock_stops)); }
  wait_ssh() { :; }
  wait_hypr() { :; }
  resource_status_json() {
    jq -cn --argjson maximum "$mock_max_cpus" --argjson cpus "$mock_cpus" \
      --argjson maxKiB "$mock_max_kib" --argjson currentKiB "$mock_kib" \
      '{cpus:{maximum:$maximum,configured:$cpus},memory:{maximumBytes:($maxKiB*1024),configuredBytes:($currentKiB*1024)},host:{safeCpus:24,safeMemoryBytes:98784247808,balancedCpus:4,balancedMemoryBytes:8589934592,performanceCpus:8,performanceMemoryBytes:17179869184,fullCpus:16,fullMemoryBytes:34359738368}}'
  }
  run_virsh() {
    case $1 in
    setvcpus)
      if [[ $4 == "--maximum" ]]; then
        (($3 >= mock_cpus)) || fail "CPU ceiling cannot shrink below current CPUs"
        mock_max_cpus=$3
      else
        (($3 <= mock_max_cpus)) || fail "CPUs cannot grow beyond their ceiling"
        mock_cpus=$3
      fi
      ;;
    setmaxmem)
      (($3 >= mock_kib)) || fail "memory ceiling cannot shrink below current memory"
      mock_max_kib=$3
      ;;
    setmem)
      (($3 <= mock_max_kib)) || fail "memory cannot grow beyond its ceiling"
      mock_kib=$3
      ;;
    start) mock_running=true; ((++mock_starts)) ;;
    *) fail "unexpected resource lifecycle operation: $*" ;;
    esac
  }

  set_resource_profile performance --json >/dev/null
  ((mock_max_cpus == 8 && mock_cpus == 8 && mock_max_kib == 16777216 && mock_kib == 16777216)) || fail "performance removes stale 64-GiB boot memory"
  ((mock_stops == 1 && mock_starts == 1)) || fail "resource repair power-cycles the running guest"
  set_resource_profile full --json >/dev/null
  ((mock_max_cpus == 16 && mock_cpus == 16 && mock_max_kib == 33554432 && mock_kib == 33554432)) || fail "full can grow after a smaller ceiling"
  set_resource_profile balanced --no-reboot --json >/dev/null
  ((mock_max_cpus == 4 && mock_cpus == 4 && mock_max_kib == 8388608 && mock_kib == 8388608)) || fail "balanced lowers current values before their ceilings"
  ((mock_stops == 2 && mock_starts == 2)) || fail "no-reboot stages config without cycling the guest"
)
pass "profile changes shrink boot allocations and preserve growth and deferred changes"

"$ROOT/bin/omarchy-lab-action" list --json | jq -e '.actions | length == 8' >/dev/null || fail "action list is structured JSON"
pass "action list is structured JSON"

"$ROOT/bin/omarchy-lab-checkpoint" list --json | jq -e '.checkpoints == []' >/dev/null || fail "empty checkpoint state is structured JSON"
pass "empty checkpoint state is structured JSON"

"$ROOT/bin/omarchy-lab-capture" list --json | jq -e '.artifacts == []' >/dev/null || fail "empty artifact state is structured JSON"
pass "empty artifact state is structured JSON"

cat >"$OMARCHY_LAB_SCENARIO_DIR/safe.json" <<'JSON'
{"name":"safe","description":"Safe argument-array scenario","steps":[{"command":["health","--json"]}]}
JSON
cat >"$OMARCHY_LAB_SCENARIO_DIR/unsafe.json" <<'JSON'
{"name":"unsafe","description":"Rejected shell command","steps":[{"command":["sh","-c","touch /tmp/no"]}]}
JSON

"$ROOT/bin/omarchy-lab-scenario" validate safe --json | jq -e '.valid and .name == "safe"' >/dev/null || fail "safe scenario validates"
pass "safe scenario validates"

if "$ROOT/bin/omarchy-lab-scenario" validate unsafe --json >/dev/null 2>&1; then
  fail "scenario validator rejects commands outside the Lab command families"
fi
pass "scenario validator rejects commands outside the Lab command families"

"$ROOT/bin/omarchy-lab-scenario" list --json | jq -e '[.scenarios[].name] | index("safe") != null and index("unsafe") == null' >/dev/null || fail "scenario list omits invalid saved files"
pass "scenario list omits invalid saved files"

branch_scenario=$(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-scenario"
  run_command_array() {
    jq -cn --argjson command "$(base64 -d <<<"$1")" '{command:$command,exitCode:0,output:"ok"}'
  }
  run_scenario checkpoint-deploy feature/searchable --branch --json
)
jq -e '.steps[1].command == ["checkout","deploy","--branch","feature/searchable","--json"]' <<<"$branch_scenario" >/dev/null || fail "checkpoint deployment scenario accepts a local branch"
pass "checkpoint deployment scenario accepts a local branch"

"$ROOT/bin/omarchy-lab-checkout" list "$ROOT" --json | jq -e '.worktrees | length > 0 and all(.[]; (.path | length > 0) and (.commit | length == 40))' >/dev/null || fail "checkout discovery returns agent-ready Git metadata"
pass "checkout discovery returns agent-ready Git metadata"

"$ROOT/bin/omarchy-lab-checkout" branches "$ROOT" --json | jq -e '.branches | length > 0 and all(.[]; (.branch | length > 0) and (.commit | length == 40) and (.checkedOut | type == "boolean"))' >/dev/null || fail "branch discovery returns searchable local refs"
pass "branch discovery returns searchable local refs"

branch_repo="$test_tmp/branch-repo"
mkdir -p "$branch_repo"
git -C "$branch_repo" init -q -b main
git -C "$branch_repo" config user.name "Lab Test"
git -C "$branch_repo" config user.email "lab-test@example.com"
printf 'main\n' >"$branch_repo/deploy-marker.txt"
git -C "$branch_repo" add deploy-marker.txt
git -C "$branch_repo" commit -qm "Add main marker"
git -C "$branch_repo" switch -qc feature/searchable
printf 'feature one\n' >"$branch_repo/deploy-marker.txt"
git -C "$branch_repo" commit -qam "Add feature marker"
feature_commit=$(git -C "$branch_repo" rev-parse HEAD)
git -C "$branch_repo" switch -q main

deployment=$(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-checkout"
  DEPLOYMENT_FILE="$test_tmp/branch-deployment.json"
  require_running_lab() { :; }
  guest_user() { echo lab; }
  push_lab() { cp "$1/deploy-marker.txt" "$test_tmp/deployed-marker.txt"; printf '%s\n' "$2" >"$test_tmp/deployed-destination.txt"; }
  lab_ssh() { :; }
  lab_reboot() { :; }
  wait_ssh() { :; }
  wait_hypr() { :; }
  deploy_source --branch feature/searchable --repository "$branch_repo" --destination /srv/omarchy --no-reboot --json
)
[[ $(<"$test_tmp/deployed-marker.txt") == "feature one" ]] || fail "branch deployment materializes the selected ref"
[[ $(<"$test_tmp/deployed-destination.txt") == "/srv/omarchy" ]] || fail "branch deployment uses the requested guest destination"
jq -e --arg repository "$branch_repo" --arg commit "$feature_commit" '.sourceKind == "branch" and .repository == $repository and .destination == "/srv/omarchy" and .branch == "feature/searchable" and .commit == $commit and .rebooted == false' <<<"$deployment" >/dev/null || fail "branch deployment records reproducible source metadata"
pass "branch deployment materializes an unchecked-out ref and records its source"

git -C "$branch_repo" switch -q feature/searchable
printf 'feature two\n' >"$branch_repo/deploy-marker.txt"
git -C "$branch_repo" commit -qam "Update feature marker"
updated_feature_commit=$(git -C "$branch_repo" rev-parse HEAD)
git -C "$branch_repo" switch -q main

sync_result=$(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-checkout"
  DEPLOYMENT_FILE="$test_tmp/branch-deployment.json"
  require_running_lab() { :; }
  guest_user() { echo lab; }
  push_lab() { cp "$1/deploy-marker.txt" "$test_tmp/deployed-marker.txt"; printf '%s\n' "$2" >"$test_tmp/deployed-destination.txt"; }
  lab_ssh() { :; }
  lab_reboot() { :; }
  wait_ssh() { :; }
  wait_hypr() { :; }
  session_lab() { :; }
  sync_checkout --json
)
[[ $(<"$test_tmp/deployed-marker.txt") == "feature two" ]] || fail "branch sync rematerializes the latest selected ref"
[[ $(<"$test_tmp/deployed-destination.txt") == "/srv/omarchy" ]] || fail "branch sync preserves the saved guest destination"
jq -e --arg commit "$updated_feature_commit" '.sourceKind == "branch" and .branch == "feature/searchable" and .commit == $commit and .mode == "sync"' <<<"$sync_result" >/dev/null || fail "branch sync retains branch metadata"
pass "branch sync rematerializes the latest commit"

mkdir -p "$test_tmp/state/artifacts/screens"
magick -size 2x2 xc:red "$test_tmp/before.png"
magick -size 2x2 xc:blue "$test_tmp/after.png"
comparison=$(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-capture"
  SCREEN_DIR="$test_tmp/state/artifacts/screens"
  capture_comparison "$test_tmp/before.png" "$test_tmp/after.png" "$test_tmp/compare.png" --json
)
jq -e '.type == "screenshot" and (.before | endswith("before.png"))' <<<"$comparison" >/dev/null || fail "comparison emits structured artifact metadata"
[[ $(magick identify -format '%wx%h' "$test_tmp/compare.png") == "4x2" ]] || fail "comparison joins both screenshots"
pass "comparison joins screenshots and emits structured metadata"

(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-gold"
  IMAGES="$test_tmp/libvirt"
  BASE_VOL=base.qcow2
  OVERLAY_VOL=overlay.qcow2
  CONFIG_FILE="$test_tmp/gold-config"
  STATE_DIR="$test_tmp/gold-state"
  KNOWN_HOSTS="$test_tmp/known-hosts"
  mkdir -p "$IMAGES" "$STATE_DIR"
  printf 'DISK=16M\n' >"$CONFIG_FILE"
  qemu-img create -q -f qcow2 "$IMAGES/$BASE_VOL" 16M
  qemu-io -c 'write -P 0x11 8192 4096' "$IMAGES/$BASE_VOL" >/dev/null
  qemu-img create -q -f qcow2 -F qcow2 -b "$IMAGES/$BASE_VOL" "$IMAGES/$OVERLAY_VOL" 16M
  qemu-io -c 'write 0 4096' "$IMAGES/$OVERLAY_VOL" >/dev/null
  mkdir -p "$CHECKPOINT_DIR"
  cp "$IMAGES/$OVERLAY_VOL" "$CHECKPOINT_DIR/pre-promotion.qcow2"
  qemu-io -c 'write -P 0x22 8192 4096' "$IMAGES/$OVERLAY_VOL" >/dev/null

  require_lab() { :; }
  find_pool() { echo test-pool; }
  domain_running() { return 1; }
  is_tty() { return 0; }
  sudo() { [[ $1 == "-v" ]]; }
  run_as_root() {
    if [[ $1 == "chown" ]]; then return 0; else command "$@"; fi
  }
  run_virsh() {
    case $1 in
    dumpxml) printf "<interface type='network'>\n<source network='default'/>\n</interface>\n" ;;
    pool-refresh) : ;;
    vol-delete) rm -f "$IMAGES/$OVERLAY_VOL" ;;
    vol-create-as) qemu-img create -q -f qcow2 -F qcow2 -b "$IMAGES/$BASE_VOL" "$IMAGES/$OVERLAY_VOL" "$4" ;;
    *) fail "unexpected mocked virsh operation: $*" ;;
    esac
  }

  promote_gold --yes >/dev/null
  [[ $(qemu-img info --output=json "$IMAGES/$BASE_VOL" | jq -r 'has("backing-filename")') == "false" ]] || fail "promoted gold is flattened"
  [[ $(qemu-img info --output=json "$IMAGES/$OVERLAY_VOL" | jq -r '."backing-filename"') == "$IMAGES/$BASE_VOL" ]] || fail "promotion creates a fresh overlay over new gold"
  [[ -f $IMAGES/base.previous.qcow2 && -f $STATE_DIR/gold.json ]] || fail "promotion retains previous gold and metadata"
  qemu-io -c 'read -P 0x11 8192 4096' "$CHECKPOINT_DIR/pre-promotion.qcow2" >/dev/null
  qemu-io -c 'write -P 0x33 8192 4096' "$IMAGES/$OVERLAY_VOL" >/dev/null
  promote_gold --yes >/dev/null
  qemu-io -c 'read -P 0x11 8192 4096' "$CHECKPOINT_DIR/pre-promotion.qcow2" >/dev/null
  jq -e '.networkSource == "default"' "$STATE_DIR/gold.json" >/dev/null || fail "promotion saves reset network"
)
pass "gold promotion flattens safely and retains one previous image"

(
  # shellcheck disable=SC1090
  source "$ROOT/bin/omarchy-lab-gold"
  CONFIG_FILE="$test_tmp/rebuild-config"
  printf 'DISK=32G\n' >"$CONFIG_FILE"
  require_lab() { :; }
  is_tty() { return 0; }
  sudo() { [[ $1 == "-v" ]]; }
  preserve_checkpoints() { :; }
  guest_user() { echo agent; }
  run_virsh() {
    if [[ $1 == "vcpucount" ]]; then echo 6
    elif [[ $1 == "dominfo" ]]; then echo 'Max memory: 8388608 KiB'
    else fail "unexpected mocked rebuild query: $*"
    fi
  }
  remove_lab() { [[ $1 == "--yes" ]]; }
  install_lab() { printf '%s\n' "$OMARCHY_LAB_USER $OMARCHY_LAB_DISK $OMARCHY_LAB_CORES $OMARCHY_LAB_RAM" >"$test_tmp/rebuild-values"; }
  rebuild_gold --yes >/dev/null
)
[[ $(<"$test_tmp/rebuild-values") == "agent 32G 6 8G" ]] || fail "gold rebuild preserves current VM sizing and user"
pass "gold rebuild preserves current VM sizing and user"
