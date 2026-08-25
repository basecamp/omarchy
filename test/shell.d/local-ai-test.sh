#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
docker_history="$test_tmp/docker-history"
docker_exists="$test_tmp/docker-exists"
docker_running="$test_tmp/docker-running"
docker_recipe="$test_tmp/docker-recipe"
served_model="$test_tmp/served-model"
docker_previous_exists="$test_tmp/docker-previous-exists"
docker_previous_running="$test_tmp/docker-previous-running"
docker_previous_recipe="$test_tmp/docker-previous-recipe"
served_previous_model="$test_tmp/served-previous-model"
notification_history="$test_tmp/notification-history"
fixtures="$test_tmp/fixtures"
mkdir -p "$mock_bin" "$test_home" "$fixtures"

cat >"$mock_bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_DOCKER_HISTORY"

case ${1:-} in
version)
  printf '%s\n' "27.0.0"
  ;;
info)
  printf '%s\n' '{"nvidia":{}}'
  ;;
inspect)
  target=${!#}
  if [[ $target == *-previous ]]; then
    exists=$OMARCHY_TEST_DOCKER_PREVIOUS_EXISTS
    running=$OMARCHY_TEST_DOCKER_PREVIOUS_RUNNING
    recipe=$OMARCHY_TEST_DOCKER_PREVIOUS_RECIPE
  else
    exists=$OMARCHY_TEST_DOCKER_EXISTS
    running=$OMARCHY_TEST_DOCKER_RUNNING
    recipe=$OMARCHY_TEST_DOCKER_RECIPE
  fi
  [[ -f $exists ]] || exit 1
  case "$*" in
  *io.omarchy.local-ai.recipe*) cat "$recipe" ;;
  *State.Running*) cat "$running" ;;
  esac
  ;;
run)
  touch "$OMARCHY_TEST_DOCKER_EXISTS"
  printf '%s\n' true >"$OMARCHY_TEST_DOCKER_RUNNING"
  while (($# > 0)); do
    if [[ $1 == "--label" && ${2:-} == io.omarchy.local-ai.recipe=* ]]; then
      recipe=${2#*=}
      printf '%s\n' "$recipe" >"$OMARCHY_TEST_DOCKER_RECIPE"
      jq -r --arg recipe "$recipe" '.recipes[] | select(.name == $recipe) | .served_name' "$OMARCHY_TEST_CATALOG" >"$OMARCHY_TEST_SERVED_MODEL"
      break
    fi
    shift
  done
  ;;
start)
  [[ -f $OMARCHY_TEST_DOCKER_EXISTS ]] || exit 1
  printf '%s\n' true >"$OMARCHY_TEST_DOCKER_RUNNING"
  ;;
stop)
  [[ -f $OMARCHY_TEST_DOCKER_EXISTS ]] || exit 1
  printf '%s\n' false >"$OMARCHY_TEST_DOCKER_RUNNING"
  ;;
rm)
  target=${!#}
  if [[ $target == *-previous ]]; then
    rm -f "$OMARCHY_TEST_DOCKER_PREVIOUS_EXISTS" "$OMARCHY_TEST_DOCKER_PREVIOUS_RUNNING" "$OMARCHY_TEST_DOCKER_PREVIOUS_RECIPE" "$OMARCHY_TEST_SERVED_PREVIOUS_MODEL"
  else
    rm -f "$OMARCHY_TEST_DOCKER_EXISTS" "$OMARCHY_TEST_DOCKER_RUNNING" "$OMARCHY_TEST_DOCKER_RECIPE" "$OMARCHY_TEST_SERVED_MODEL"
  fi
  ;;
rename)
  if [[ $3 == *-previous ]]; then
    mv "$OMARCHY_TEST_DOCKER_EXISTS" "$OMARCHY_TEST_DOCKER_PREVIOUS_EXISTS"
    mv "$OMARCHY_TEST_DOCKER_RUNNING" "$OMARCHY_TEST_DOCKER_PREVIOUS_RUNNING"
    mv "$OMARCHY_TEST_DOCKER_RECIPE" "$OMARCHY_TEST_DOCKER_PREVIOUS_RECIPE"
    mv "$OMARCHY_TEST_SERVED_MODEL" "$OMARCHY_TEST_SERVED_PREVIOUS_MODEL"
  else
    mv "$OMARCHY_TEST_DOCKER_PREVIOUS_EXISTS" "$OMARCHY_TEST_DOCKER_EXISTS"
    mv "$OMARCHY_TEST_DOCKER_PREVIOUS_RUNNING" "$OMARCHY_TEST_DOCKER_RUNNING"
    mv "$OMARCHY_TEST_DOCKER_PREVIOUS_RECIPE" "$OMARCHY_TEST_DOCKER_RECIPE"
    mv "$OMARCHY_TEST_SERVED_PREVIOUS_MODEL" "$OMARCHY_TEST_SERVED_MODEL"
  fi
  ;;
logs) ;;
esac
SH

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
for arg in "$@"; do
  case $arg in
  *raw.github.test/0xSero/inference-index/main/catalog.json) cat "$OMARCHY_TEST_FIXTURES/registry-catalog.json"; exit 0 ;;
  *raw.github.test/0xSero/inference-index/main/hardware/rtx-3090-24gb/registry-fast/recipe.json) cat "$OMARCHY_TEST_FIXTURES/registry-leaf.json"; exit 0 ;;
  *raw.github.test/*) exit 22 ;;
  */v1/models)
    if [[ ${OMARCHY_TEST_ACCEPT_FAIL:-false} == "true" ]]; then
      printf '%s\n' '{"data":[]}'
    elif [[ -f $OMARCHY_TEST_SERVED_MODEL ]]; then
      jq -n --arg model "$(cat "$OMARCHY_TEST_SERVED_MODEL")" '{data: [{id: $model}]}'
    else
      printf '%s\n' '{"data":[]}'
    fi
    exit 0
    ;;
  */v1/chat/completions) printf '%s\n' '{"choices":[{"message":{"content":"ready"}}]}'; exit 0 ;;
  esac
done
exit 0
SH

cat >"$mock_bin/ss" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_HISTORY"
SH

cat >"$mock_bin/omarchy-test-noop" <<'SH'
#!/bin/bash
exit 0
SH

for command in omarchy-shell omarchy-bar; do
  ln -s omarchy-test-noop "$mock_bin/$command"
done

# macOS ships Bash 3 at /bin/bash while Omarchy targets Bash 5. Wrapping only
# the commands under test lets contributors select a Bash 5 binary locally;
# Linux CI keeps using /bin/bash.
for command in omarchy-ai-doctor omarchy-ai-list omarchy-ai-logs omarchy-ai-remove omarchy-ai-run omarchy-ai-setup omarchy-ai-start omarchy-ai-status omarchy-ai-stop omarchy-ai-sync omarchy-ai-toggle; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
exec "${OMARCHY_TEST_BASH:-/bin/bash}" "$OMARCHY_PATH/bin/${0##*/}" "$@"
SH
done

chmod +x "$mock_bin"/*

export HOME="$test_home"
export XDG_STATE_HOME="$test_tmp/ignored-xdg-state"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_DOCKER_HISTORY="$docker_history"
export OMARCHY_TEST_DOCKER_EXISTS="$docker_exists"
export OMARCHY_TEST_DOCKER_RUNNING="$docker_running"
export OMARCHY_TEST_DOCKER_RECIPE="$docker_recipe"
export OMARCHY_TEST_SERVED_MODEL="$served_model"
export OMARCHY_TEST_DOCKER_PREVIOUS_EXISTS="$docker_previous_exists"
export OMARCHY_TEST_DOCKER_PREVIOUS_RUNNING="$docker_previous_running"
export OMARCHY_TEST_DOCKER_PREVIOUS_RECIPE="$docker_previous_recipe"
export OMARCHY_TEST_SERVED_PREVIOUS_MODEL="$served_previous_model"
export OMARCHY_TEST_NOTIFICATION_HISTORY="$notification_history"
export OMARCHY_TEST_FIXTURES="$fixtures"
export OMARCHY_TEST_CATALOG="$ROOT/default/omarchy/local-ai.json"

catalog="$ROOT/default/omarchy/local-ai.json"
jq -e '.port == 8000 and ([.recipes[].name] == ["fast", "smart"])' "$catalog" >/dev/null ||
  fail "local AI catalog carries the expected recipes and port"
jq -e '.recipes[] | select(.name == "fast") | .status == "validated"' "$catalog" >/dev/null ||
  fail "fast is the validated shipped recipe"
jq -e '.recipes[] | select(.name == "smart") | .status == "candidate"' "$catalog" >/dev/null ||
  fail "smart remains a candidate"
jq -e '[.. | strings | contains("\n")] | any | not' "$catalog" >/dev/null ||
  fail "no recipe string contains a newline"
if grep -Eq -- '--disable[^ ]*cuda-graph|--enforce-eager' "$catalog"; then
  fail "recipes keep CUDA graphs enabled"
fi
pass "catalog distinguishes validated and candidate recipes"

hardware_json() {
  local count="$1" total="${2:-24564}" free
  free="${3:-$total}"
  jq -n --argjson count "$count" --argjson total "$total" --argjson free "$free" '
    [range(0; $count) | {index: ., name: "NVIDIA GeForce RTX 3090", uuid: ("GPU-" + (. | tostring)), total_vram_mb: $total, free_vram_mb: $free, compute_capability: "8.6"}] as $devices
    | {schema_version: 1, hardware_id: ("rtx-3090-24gb-x" + ($count | tostring)), family_id: "rtx-3090", vendor: "nvidia", devices: $devices, total_vram_mb: ($total * $count), free_vram_mb: ($free * $count), runtime: {name: "docker", installed: true, ready: true, version: "27.0.0", nvidia: true}, disk_free_bytes: 107374182400}'
}

one_gpu=$(hardware_json 1)
busy_gpu=$(hardware_json 1 24564 1024)
four_gpus=$(hardware_json 4)

listing=$(OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-list --json)
[[ $(jq -r '.state' <<<"$listing") == "not-setup" ]] || fail "listing reports initial state"
[[ $(jq -r '.gpus | length' <<<"$listing") == "1" ]] || fail "listing carries one hardware snapshot"
jq -e '.recipes[] | select(.name == "fast") | .compatible and .available and .fits' <<<"$listing" >/dev/null ||
  fail "validated fast is runnable on one 24 GB GPU"
jq -e '.recipes[] | select(.name == "smart") | (.status == "candidate") and (.fits | not)' <<<"$listing" >/dev/null ||
  fail "candidate smart is visible but not runnable"
listing=$(OMARCHY_AI_HARDWARE_JSON="$four_gpus" omarchy-ai-list --json)
jq -e '.recipes[] | select(.name == "smart") | .compatible and (.available | not) and (.fits | not)' <<<"$listing" >/dev/null ||
  fail "candidate status wins over compatible hardware"
pass "listing preserves the panel contract and validation gate"

plan=$(OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-run fast --dry-run --json)
jq -e '.ok and (.recipe.name == "fast") and .availability.available and .plan.port_available' <<<"$plan" >/dev/null ||
  fail "dry-run returns an available validated plan"
jq -e '.plan.docker_argv | (index("127.0.0.1:8000:8000") != null) and (index("--cap-drop") == null) and (index("--security-opt") == null)' <<<"$plan" >/dev/null ||
  fail "plan binds locally and preserves the validated container recipe"
selection_catalog="$test_tmp/selection-catalog.json"
jq '(.recipes[] | select(.name == "fast")) |= del(.scale)' "$catalog" >"$selection_catalog"
mixed_gpus=$(hardware_json 2 | jq '.devices[0].free_vram_mb = 1024 | .devices[1].free_vram_mb = .devices[1].total_vram_mb | .free_vram_mb = ([.devices[].free_vram_mb] | add)')
selection=$(OMARCHY_AI_CATALOG="$selection_catalog" OMARCHY_AI_HARDWARE_JSON="$mixed_gpus" omarchy-ai-run fast --dry-run --json)
jq -e '.availability.available and .selected_device_ids == [1]' <<<"$selection" >/dev/null ||
  fail "planner selects the free compatible GPU before a busy lower-index GPU"
plan=$(OMARCHY_AI_HARDWARE_JSON="$four_gpus" omarchy-ai-plan fast --json)
jq -e '.recipe.gpu_count == 4 and .selected_device_ids == [0, 1, 2, 3] and (.plan.docker_argv | (index("device=0,1,2,3") != null) and (index("TP=4") != null))' <<<"$plan" >/dev/null ||
  fail "one recipe scales its topology and selected devices to four GPUs"
if OMARCHY_AI_HARDWARE_JSON="$four_gpus" omarchy-ai-run smart --json >"$test_tmp/smart-output"; then
  fail "runner refuses a candidate recipe"
fi
[[ $(jq -r '.error.code' "$test_tmp/smart-output") == "UNVALIDATED_RECIPE" ]] ||
  fail "candidate refusal is machine-readable"
pass "planner is inspectable and runner enforces validation"

jq -n '{providers: {anthropic: {api: "anthropic"}}}' >"$test_home/.models-original"
jq -n '{defaultProvider: "anthropic", defaultModel: "opus"}' >"$test_home/.settings-original"
for agent in pi omp; do
  mkdir -p "$test_home/.$agent/agent"
  cp "$test_home/.models-original" "$test_home/.$agent/agent/models.json"
  cp "$test_home/.settings-original" "$test_home/.$agent/agent/settings.json"
done

: >"$docker_history"
printf '{broken\n' >"$test_home/.pi/agent/models.json"
if OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-run fast >"$test_tmp/invalid-config-output" 2>&1; then
  fail "setup refuses to overwrite malformed agent configuration"
fi
if grep -q '^run ' "$docker_history"; then
  fail "agent configuration is validated before the serving container changes"
fi
cp "$test_home/.models-original" "$test_home/.pi/agent/models.json"

: >"$docker_history"
if OMARCHY_AI_HARDWARE_JSON="$one_gpu" OMARCHY_TEST_ACCEPT_FAIL=true OMARCHY_AI_ACCEPT_TIMEOUT=0 omarchy-ai-run fast >"$test_tmp/failed-first-output" 2>&1; then
  fail "failed first setup does not report success"
fi
[[ -e $docker_exists && $(cat "$docker_running") == "false" ]] ||
  fail "failed first setup stops the container without deleting its diagnostics"
grep -q 'logs preserved' "$test_tmp/failed-first-output" || fail "failed first setup explains how to inspect preserved logs"
omarchy-ai-logs >/dev/null || fail "logs remain available after failed first setup"
docker rm --force omarchy-local-ai >/dev/null

: >"$docker_history"
OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-run fast >/dev/null
grep -q '^run ' "$docker_history" || fail "setup launches the serving container"
state_recipe="$test_home/.local/state/omarchy/local-ai/recipe.json"
[[ $(jq -r '.recipe_id' "$state_recipe") == "fast" ]] || fail "setup records the active recipe"
[[ ! -e $XDG_STATE_HOME/omarchy/local-ai/recipe.json ]] || fail "state does not split across XDG and Omarchy paths"
for agent in pi omp; do
  models="$test_home/.$agent/agent/models.json"
  settings="$test_home/.$agent/agent/settings.json"
  [[ $(jq -r '.providers.local.baseUrl' "$models") == "http://127.0.0.1:8000/v1" ]] || fail "$agent points at the local endpoint"
  jq -e '.providers.local.models[0] | .reasoning and (.input == ["text", "image"])' "$models" >/dev/null ||
    fail "$agent preserves reasoning and vision metadata"
  [[ $(jq -r '.defaultProvider' "$settings") == "anthropic" ]] || fail "$agent keeps a foreign default provider"
done
listing=$(OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-list --json)
jq -e '.state == "ready" and .ready and .active == "fast" and .model == "Qwen3.8-27B" and .port == 8000' <<<"$listing" >/dev/null ||
  fail "listing reports the accepted running model"
doctor=$(OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-doctor --json)
jq -e '.ok and (.checks[] | select(.id == "port") | .detail | contains("managed service"))' <<<"$doctor" >/dev/null ||
  fail "doctor treats the managed service as healthy rather than a port or capacity conflict"
rm -f "$served_model"
loading=$(OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-list --json)
[[ $(jq -r '.state' <<<"$loading") == "loading" ]] || fail "listing distinguishes loading from ready"
jq -r '.recipes[] | select(.name == "fast") | .served_name' "$catalog" >"$served_model"
: >"$docker_history"
OMARCHY_AI_HARDWARE_JSON="$busy_gpu" omarchy-ai-run fast >/dev/null
if grep -Eq '^(run|start|stop|rename) ' "$docker_history"; then
  fail "re-running the active recipe does not replace its own container"
fi
pass "setup accepts a completion and configures agents without stealing defaults"

alternate_catalog="$test_tmp/alternate-catalog.json"
jq '.recipes += [(.recipes[] | select(.name == "fast") | .name = "fast-alt" | .label = "Fast alternate" | .served_name = "Qwen3.8-27B-alt")]' "$catalog" >"$alternate_catalog"
: >"$docker_history"
OMARCHY_AI_CATALOG="$alternate_catalog" OMARCHY_TEST_CATALOG="$alternate_catalog" OMARCHY_AI_HARDWARE_JSON="$busy_gpu" omarchy-ai-run fast-alt >/dev/null
grep -q '^stop omarchy-local-ai$' "$docker_history" || fail "switch stops the previous container"
grep -q '^rename omarchy-local-ai omarchy-local-ai-previous$' "$docker_history" || fail "switch preserves the previous container for rollback"
[[ $(jq -r '.recipe_id' "$state_recipe") == "fast-alt" ]] || fail "accepted switch updates state"

: >"$docker_history"
if OMARCHY_AI_CATALOG="$alternate_catalog" OMARCHY_TEST_CATALOG="$alternate_catalog" OMARCHY_AI_HARDWARE_JSON="$one_gpu" OMARCHY_TEST_ACCEPT_FAIL=true OMARCHY_AI_ACCEPT_TIMEOUT=0 omarchy-ai-run fast >/dev/null 2>&1; then
  fail "failed replacement does not report success"
fi
[[ $(jq -r '.recipe_id' "$state_recipe") == "fast-alt" ]] || fail "failed replacement preserves prior state"
[[ $(cat "$docker_recipe") == "fast-alt" && $(cat "$docker_running") == "true" ]] ||
  fail "failed replacement restores the prior running container"
pass "model switching rolls back until the replacement passes acceptance"

for agent in pi omp; do
  jq '.providers.afterSetup = {api: "openai"}' "$test_home/.$agent/agent/models.json" >"$test_tmp/models" && mv "$test_tmp/models" "$test_home/.$agent/agent/models.json"
  jq '.theme = "dark"' "$test_home/.$agent/agent/settings.json" >"$test_tmp/settings" && mv "$test_tmp/settings" "$test_home/.$agent/agent/settings.json"
done

: >"$docker_history"
omarchy-ai-stop >/dev/null
grep -q '^stop omarchy-local-ai$' "$docker_history" || fail "stop unloads the managed container"
if omarchy-ai-status >/dev/null; then
  fail "status is nonzero while stopped"
fi
omarchy-ai-start >/dev/null
[[ $(cat "$docker_running") == "true" ]] || fail "start reloads the configured recipe"
pass "start and stop share the native lifecycle"

touch "$docker_previous_exists"
omarchy-ai-remove >/dev/null
[[ ! -e $state_recipe ]] || fail "remove clears active state"
[[ ! -e $docker_exists ]] || fail "remove deletes the managed container"
[[ ! -e $docker_previous_exists ]] || fail "remove clears a stale rollback container"
for agent in pi omp; do
  jq -e '.providers.anthropic.api == "anthropic" and .providers.afterSetup.api == "openai" and (.providers.local == null)' "$test_home/.$agent/agent/models.json" >/dev/null ||
    fail "remove restores $agent local provider without losing later edits"
  jq -e '.defaultProvider == "anthropic" and .defaultModel == "opus" and .theme == "dark"' "$test_home/.$agent/agent/settings.json" >/dev/null ||
    fail "remove restores $agent defaults without losing later edits"
done
pass "remove restores agent configuration and preserves caches"

jq -n '{
  schema_version: "inference-index/catalog-v1",
  recipes: [{
    id: "registry-fast",
    hardware_slug: "rtx-3090-24gb",
    status: "validated",
    launchable_by_cli: true,
    runtime_kind: "docker",
    recipe_path: "hardware/rtx-3090-24gb/registry-fast/recipe.json"
  }]
}' >"$fixtures/registry-catalog.json"
jq -n '{
  schema_version: "inference-index/v1",
  id: "registry-fast",
  status: "validated",
  profile: "tp1",
  model: {
    slug: "qwen3.8-27b",
    name: "Qwen3.8-27B",
    source: "test/Qwen3.8-27B-AWQ-INT4",
    revision: "0123456789abcdef0123456789abcdef01234567",
    served_name: "Qwen3.8-27B-registry"
  },
  weights: {slug: "awq-int4", format: "AWQ", precision: "INT4 W4A16", size_gb: 20},
  hardware: {slug: "rtx-3090-24gb", accelerator: "NVIDIA GeForce RTX 3090 24GB", count: 1, memory_gb_each: 24},
  engine: {name: "vllm", version: "0.27.1", graph_mode: "full-and-piecewise"},
  runtime: {
    kind: "docker",
    image: "ghcr.io/test/registry-fast@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    container_port: 8000,
    host_port: 12434,
    ipc: "host",
    shm_size: "16g",
    environment: {REGISTRY_TEST: "1"},
    mounts: [{source: "~/.cache/huggingface", target: "/root/.cache/huggingface", read_only: false}],
    arguments: ["--model", "test/Qwen3.8-27B-AWQ-INT4", "--tensor-parallel-size", "1"]
  },
  serving: {api: "openai/v1", tensor_parallel: 1, configured_max_context_tokens: 131072},
  capabilities: {chat: true, reasoning: true, tools: true, vision: true}
}' >"$fixtures/registry-leaf.json"
OMARCHY_AI_API=off OMARCHY_AI_GITHUB_RAW="https://raw.github.test" omarchy-ai-sync >"$test_tmp/sync-output"
cache="$test_home/.local/state/omarchy/local-ai/catalog.json"
jq -e '.recipes[] | select(.name == "registry-fast") | .source == "github:0xSero/inference-index" and .status == "validated" and .registry_path == "hardware/rtx-3090-24gb/registry-fast/recipe.json"' "$cache" >/dev/null ||
  fail "sync preserves the canonical registry identity and validation"
listing=$(OMARCHY_AI_CATALOG="$cache" OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-list --json)
jq -e '.recipes[] | select(.name == "registry-fast") | .compatible and .available and .fits' <<<"$listing" >/dev/null ||
  fail "validated registry recipes become runnable on matching hardware"
plan=$(OMARCHY_AI_CATALOG="$cache" OMARCHY_AI_HARDWARE_JSON="$one_gpu" omarchy-ai-run registry-fast --dry-run --json)
jq -e '
  .ok
  and .plan.port == 12434
  and (.plan.docker_argv | index("127.0.0.1:12434:8000") != null)
  and (.plan.docker_argv | index("ghcr.io/test/registry-fast@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") != null)
  and (.plan.docker_argv | index("--tensor-parallel-size") != null)
' <<<"$plan" >/dev/null || fail "planner translates the canonical leaf without replacing its launch contract"
if jq -r '.plan.docker_argv[]' <<<"$plan" | grep -Eq -- '--disable[^ ]*cuda-graph|--enforce-eager'; then
  fail "registry adapter keeps CUDA graphs enabled"
fi
cp "$cache" "$test_tmp/catalog-before-failed-sync.json"
if OMARCHY_AI_API=off OMARCHY_AI_GITHUB_RAW="https://missing.github.test" omarchy-ai-sync >"$test_tmp/failed-sync-output" 2>&1; then
  fail "an unavailable configured registry reports sync failure"
fi
cmp -s "$test_tmp/catalog-before-failed-sync.json" "$cache" || fail "failed sync preserves the last good catalog"
pass "sync consumes canonical registry leaves without weakening validation"

panel_dir="$ROOT/shell/plugins/panels/local-ai"
jq -e '.id == "omarchy.local-ai" and .entryPoints.barWidget == "Panel.qml"' "$panel_dir/manifest.json" >/dev/null ||
  fail "local AI panel manifest is well-formed"
grep -q 'omarchy-ai-list' "$panel_dir/Panel.qml" || fail "panel reads the shared list contract"
grep -q 'modelData.fits' "$panel_dir/Panel.qml" || fail "panel gates selection on the validated fit verdict"
grep -q 'Util.shellQuote' "$panel_dir/Panel.qml" || fail "panel quotes recipe launch commands with the shared helper"
grep -q 'info.state === "loading"' "$panel_dir/Panel.qml" || fail "panel renders loading separately from readiness"
jq -e '.bar.layout.center | map(.id) | index("omarchy.local-ai")' "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "default bar layout carries the local AI panel"
pass "panel is wired to the validated CLI contract"
