#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
docker_history="$test_tmp/docker-history"
notification_history="$test_tmp/notification-history"
fixtures="$test_tmp/fixtures"
mkdir -p "$mock_bin" "$test_home" "$fixtures"

cat >"$mock_bin/nvidia-smi" <<'SH'
#!/bin/bash
[[ -n ${OMARCHY_TEST_VRAM_MB:-} ]] || exit 1
printf '%s\n' "$OMARCHY_TEST_VRAM_MB"
SH

cat >"$mock_bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_DOCKER_HISTORY"
case $1 in
ps) [[ ${OMARCHY_TEST_CONTAINER_EXISTS:-false} == "true" ]] && echo "abc123" ;;
inspect) printf '%s\n' "${OMARCHY_TEST_DOCKER_RUNNING:-true}" ;;
esac
exit 0
SH

# curl serves the health/completion endpoints and, for sync, GitHub fixtures
# routed by URL substring.
cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
for arg in "$@"; do
  case $arg in
  *api.github.test/users/*) cat "$OMARCHY_TEST_FIXTURES/repos.json"; exit 0 ;;
  *raw.github.test/*/recipe-repo/*) cat "$OMARCHY_TEST_FIXTURES/omarchy-recipe.json"; exit 0 ;;
  *raw.github.test/*) exit 22 ;;
  *chat/completions*) printf '%s\n' '{"choices":[{"message":{"content":"ready"}}]}'; exit 0 ;;
  esac
done
exit 0
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_HISTORY"
SH

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
! command -v "$1" >/dev/null
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
command -v "$1" >/dev/null
SH

cat >"$mock_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
printf '%s' "${OMARCHY_TEST_DEFAULT_AGENT:-}"
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
echo "unexpected sudo: $*" >&2
exit 1
SH

cat >"$mock_bin/omarchy-test-noop" <<'SH'
#!/bin/bash
exit 0
SH

for command in omarchy-shell omarchy-bar omarchy-pkg-add; do
  ln -s omarchy-test-noop "$mock_bin/$command"
done

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_DOCKER_HISTORY="$docker_history"
export OMARCHY_TEST_NOTIFICATION_HISTORY="$notification_history"
export OMARCHY_TEST_FIXTURES="$fixtures"

catalog="$ROOT/default/omarchy/local-ai.json"
jq -e '.port and .sources and ([.recipes[].name] == ["fast", "smart"])' "$catalog" >/dev/null ||
  fail "local AI catalog ships exactly the fast and smart recipes"
jq -e '[.recipes[].min_vram_mb] | min <= 24000' "$catalog" >/dev/null ||
  fail "smallest local AI recipe fits a 24 GB GPU"
# The arg parser splits on newlines (jq -r | mapfile), so a multi-line arg
# silently shatters into separate docker args.
jq -e '[.. | strings | contains("\n")] | any | not' "$catalog" >/dev/null ||
  fail "no recipe string contains a newline"
if grep -Eq -- '--disable[^ ]*cuda-graph|--enforce-eager' "$catalog"; then
  fail "recipes keep CUDA graphs enabled"
fi
pass "local AI catalog is fast and smart, nothing else"

port=$(jq -r '.port' "$catalog")
fast_image=$(jq -r '.recipes[0].image' "$catalog")
fast_served=$(jq -r '.recipes[0].served_name' "$catalog")
smart_image=$(jq -r '.recipes[1].image' "$catalog")
smart_model=$(jq -r '.recipes[1].model' "$catalog")
smart_served=$(jq -r '.recipes[1].served_name' "$catalog")
one_gpu=24564
two_gpus=$'24564\n24564'
four_gpus=$'24564\n24564\n24564\n24564'

# A single 24 GB GPU auto-picks fast at TP1.
plan=$(OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-setup --dry-run)
for expected in "$fast_image" "--shm-size 32g" "--volume $test_home/.cache/omarchy-local-ai/models:/models" \
  "127.0.0.1:$port:8000" "--gpus all" "--restart unless-stopped"; do
  [[ $plan == *"$expected"* ]] || fail "single-GPU plan carries [$expected]" "plan: $plan"
done
[[ $plan != *"--env TP="* ]] || fail "a single GPU serves fast without a TP override" "plan: $plan"
pass "a 24 GB GPU gets the fast recipe at TP1"

# One recipe scales itself: fast picks its TP from the qualifying GPU count.
plan=$(OMARCHY_TEST_VRAM_MB=$two_gpus omarchy-ai-setup fast --dry-run)
[[ $plan == *"--env TP=2"* ]] || fail "fast scales to TP2 on a 2-GPU box" "plan: $plan"
plan=$(OMARCHY_TEST_VRAM_MB=$four_gpus omarchy-ai-setup fast --dry-run)
[[ $plan == *"--env TP=4"* ]] || fail "fast scales to TP4 on a 4-GPU box" "plan: $plan"
pass "fast scales its tensor parallelism to the GPU count"

# Smart needs two cards, wins the auto-pick when they exist, and scales to four.
plan=$(OMARCHY_TEST_VRAM_MB=$two_gpus omarchy-ai-setup --dry-run)
for expected in "$smart_image" "--model $smart_model" "--served-model-name $smart_served" \
  "--tensor-parallel-size 2" "--max-model-len 131072"; do
  [[ $plan == *"$expected"* ]] || fail "2-GPU auto-pick serves smart [$expected]" "plan: $plan"
done
plan=$(OMARCHY_TEST_VRAM_MB=$four_gpus omarchy-ai-setup --dry-run)
[[ $plan == *"--tensor-parallel-size 4"* && $plan == *"--max-model-len 131072"* ]] ||
  fail "4-GPU auto-pick serves smart at TP4 with the full context" "plan: $plan"
if OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-setup smart --dry-run >"$test_tmp/gpu-count-output" 2>&1; then
  fail "setup refuses smart on a single-GPU box"
fi
grep -q "2×" "$test_tmp/gpu-count-output" || fail "the refusal explains the GPU-count requirement"
pass "smart needs two cards and wins the auto-pick when they exist"

# Recipes are addressable by name; unknown names list what exists.
if OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-setup no-such-recipe --dry-run >"$test_tmp/unknown-output" 2>&1; then
  fail "setup refuses an unknown recipe name"
fi
grep -q "fast" "$test_tmp/unknown-output" || fail "unknown recipe error lists the known recipes"
pass "recipes are addressable by name"

# Multi-GPU boxes read the largest card; small cards and missing GPUs are refused.
plan=$(OMARCHY_TEST_VRAM_MB=$'11264\n24564' omarchy-ai-setup --dry-run)
[[ $plan == *"$fast_image"* ]] || fail "setup sizes a multi-GPU box by its qualifying cards"
plan=$(OMARCHY_TEST_VRAM_MB=$two_gpus OMARCHY_AI_GPUS=2,3 omarchy-ai-setup --dry-run)
[[ $plan == *"--gpus device=2,3"* ]] || fail "OMARCHY_AI_GPUS confines the container to a GPU subset" "plan: $plan"
if OMARCHY_TEST_VRAM_MB=16384 omarchy-ai-setup --dry-run >"$test_tmp/small-gpu-output" 2>&1; then
  fail "setup refuses a 16 GB GPU"
fi
grep -q "24 GB" "$test_tmp/small-gpu-output" || fail "setup explains the 24 GB requirement"
if omarchy-ai-setup --dry-run >"$test_tmp/no-gpu-output" 2>&1; then
  fail "setup refuses a box without an NVIDIA GPU"
fi
grep -q "NVIDIA" "$test_tmp/no-gpu-output" || fail "setup explains the NVIDIA requirement"
pass "setup refuses unsupported hardware with an explanation"

# A full (mocked) setup serves the model and wires the agents.
: >"$docker_history"
OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-setup >"$test_tmp/setup-output"
grep -q "^run " "$docker_history" || fail "setup launches the serving container"
state_recipe="$test_home/.local/state/omarchy/local-ai/recipe.json"
[[ -f $state_recipe ]] || fail "setup records its recipe"
[[ $(jq -r '.name' "$state_recipe") == "fast" ]] || fail "recorded recipe names the tier"
[[ $(jq -r '.port' "$state_recipe") == "$port" ]] || fail "recorded recipe carries the serving port"
[[ $(jq -r '.context_window' "$state_recipe") == "8192" ]] || fail "recorded recipe carries the scaled context"

for agent in pi omp; do
  models="$test_home/.$agent/agent/models.json"
  settings="$test_home/.$agent/agent/settings.json"
  [[ $(jq -r '.providers.local.baseUrl' "$models") == "http://127.0.0.1:$port/v1" ]] ||
    fail "$agent local provider points at the local endpoint"
  [[ $(jq -r '.providers.local.models[0].id' "$models") == "$fast_served" ]] ||
    fail "$agent local provider carries the served model"
  [[ $(jq -r '.providers.local.models[0].reasoning' "$models") == "true" ]] ||
    fail "$agent local provider carries the reasoning flag"
  [[ $(jq -c '.providers.local.models[0].input' "$models") == '["text","image"]' ]] ||
    fail "$agent local provider carries image input for a vision recipe"
  [[ $(jq -r '.defaultProvider' "$settings") == "local" ]] ||
    fail "$agent adopts the local provider when it has no default"
done
grep -qz "Local AI ready" "$notification_history" || fail "setup announces readiness"
pass "setup serves the model and wires pi and omp"

# The scale step lands in the wiring: a 4-GPU smart setup carries its context.
OMARCHY_TEST_VRAM_MB=$four_gpus omarchy-ai-setup >/dev/null
[[ $(jq -r '.name' "$state_recipe") == "smart" ]] || fail "a 4-GPU box auto-serves smart"
[[ $(jq -r '.context_window' "$state_recipe") == "131072" ]] ||
  fail "the 4-GPU scale step lands in the recorded recipe"
[[ $(jq -r '.providers.local.models[0].contextWindow' "$test_home/.pi/agent/models.json") == "131072" ]] ||
  fail "the scaled context reaches the agent provider"
pass "the scale step lands in the recorded recipe and the wiring"

# Switching recipes keeps our own default model current in the agents.
[[ $(jq -r '.defaultModel' "$test_home/.omp/agent/settings.json") == "$smart_served" ]] ||
  fail "serving smart updates the agent's default model"
OMARCHY_TEST_VRAM_MB=$four_gpus omarchy-ai-setup fast >/dev/null
[[ $(jq -r '.defaultModel' "$test_home/.omp/agent/settings.json") == "$fast_served" ]] ||
  fail "switching back to fast restores the default model"
pass "switching recipes keeps the agent wiring current"

# Re-setup respects an existing provider choice.
jq -n '{defaultProvider: "anthropic", defaultModel: "opus"}' >"$test_home/.pi/agent/settings.json"
OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-setup >/dev/null
[[ $(jq -r '.defaultProvider' "$test_home/.pi/agent/settings.json") == "anthropic" ]] ||
  fail "setup leaves an existing default provider alone"
pass "setup leaves an existing default provider alone"

# The listing is the one contract the panel and humans share.
listing=$(OMARCHY_TEST_VRAM_MB=$one_gpu omarchy-ai-list --json)
[[ $(jq -r '.state' <<<"$listing") == "running" ]] || fail "listing reports the serving state"
[[ $(jq -r '.active' <<<"$listing") == "fast" ]] || fail "listing reports the active recipe"
[[ $(jq -r '.model' <<<"$listing") == "$fast_served" ]] ||
  fail "listing carries the served model id clients must send"
[[ $(jq -r '.recipes[0].name' <<<"$listing") == "smart" ]] || fail "listing sorts smart first"
jq -e '.recipes[] | select(.name == "fast") | .fits and .active' <<<"$listing" >/dev/null ||
  fail "listing marks the active recipe as fitting"
jq -e '.recipes[] | select(.name == "smart") | .fits | not' <<<"$listing" >/dev/null ||
  fail "listing marks smart as not fitting a single GPU"
listing=$(OMARCHY_TEST_VRAM_MB=$four_gpus omarchy-ai-list --json)
jq -e '[.recipes[].fits] | all' <<<"$listing" >/dev/null || fail "every recipe fits a 4-GPU box"
[[ $(jq -r '.gpus | length' <<<"$listing") == "4" ]] || fail "the listing reports the GPU count"
listing=$(OMARCHY_TEST_VRAM_MB=16384 omarchy-ai-list --json)
jq -e '[.recipes[].fits] | all(. == false)' <<<"$listing" >/dev/null ||
  fail "listing marks nothing as fitting on a small GPU"
pass "the listing reports state, fit, and sorted recipes"

# Sync merges GitHub recipes over the shipped catalog into the cache.
jq -n '[{name: "recipe-repo", default_branch: "main"}, {name: "no-recipe", default_branch: "main"}]' >"$fixtures/repos.json"
jq -n '{name: "step3-flash", label: "Step 3 Flash (test)", min_vram_mb: 90000, image: "ghcr.io/test/step3:latest"}' \
  >"$fixtures/omarchy-recipe.json"
OMARCHY_AI_GITHUB_API="https://api.github.test" OMARCHY_AI_GITHUB_RAW="https://raw.github.test" \
  omarchy-ai-sync >"$test_tmp/sync-output"
cache="$test_home/.local/state/omarchy/local-ai/catalog.json"
[[ -f $cache ]] || fail "sync writes the catalog cache"
jq -e '.recipes[] | select(.name == "step3-flash") | .source == "github:0xSero/recipe-repo"' "$cache" >/dev/null ||
  fail "sync merges a GitHub recipe with its source"
[[ $(jq -r '.recipes[0].name' "$cache") == "step3-flash" ]] ||
  fail "sync sorts the merged catalog largest-first"
listing=$(OMARCHY_TEST_VRAM_MB=98304 omarchy-ai-list --json)
jq -e '.recipes[] | select(.name == "step3-flash") | .fits' <<<"$listing" >/dev/null ||
  fail "listing reads the synced cache"
rm -f "$cache"
pass "sync merges GitHub recipes into the catalog cache"

# Status reflects the container and drives the toggle.
[[ $(omarchy-ai-status) == "fast on 127.0.0.1:$port" ]] || fail "status reports the running server"
: >"$docker_history"
omarchy-ai-toggle
grep -q "^stop omarchy-local-ai$" "$docker_history" || fail "toggle unloads a running server"
: >"$docker_history"
OMARCHY_TEST_DOCKER_RUNNING=false omarchy-ai-toggle
grep -q "^start omarchy-local-ai$" "$docker_history" || fail "toggle loads a stopped server"
if OMARCHY_TEST_DOCKER_RUNNING=false omarchy-ai-status >/dev/null; then
  fail "status reports a stopped server with a nonzero exit"
fi
pass "status and toggle track the serving container"

# Remove takes out the container, the wiring, and the state, but not foreign settings.
: >"$docker_history"
omarchy-ai-remove >/dev/null
grep -q "^rm --force omarchy-local-ai$" "$docker_history" || fail "remove deletes the container"
[[ $(jq -r '.providers.local // "gone"' "$test_home/.pi/agent/models.json") == "gone" ]] ||
  fail "remove drops the local provider"
[[ $(jq -r '.defaultProvider' "$test_home/.pi/agent/settings.json") == "anthropic" ]] ||
  fail "remove leaves a foreign default provider alone"
[[ $(jq -r '.defaultProvider // "gone"' "$test_home/.omp/agent/settings.json") == "gone" ]] ||
  fail "remove clears a default provider it set"
[[ ! -e $test_home/.local/state/omarchy/local-ai ]] || fail "remove clears the local AI state"
status_exit=0
omarchy-ai-status >/dev/null || status_exit=$?
(( status_exit == 2 )) || fail "status reports not set up after removal"
pass "remove takes out the container, the wiring, and the state"

# The panel ships as a first-party plugin wired to these commands.
panel_dir="$ROOT/shell/plugins/panels/local-ai"
jq -e '.id == "omarchy.local-ai" and .entryPoints.barWidget == "Panel.qml"' \
  "$panel_dir/manifest.json" >/dev/null || fail "local AI panel manifest is well-formed"
[[ -f $panel_dir/Panel.qml ]] || fail "local AI panel entry point exists"
grep -q "omarchy-ai-list" "$panel_dir/Panel.qml" || fail "panel reads the omarchy-ai-list contract"
grep -q "omarchy-ai-toggle" "$panel_dir/Panel.qml" || fail "panel toggles with omarchy-ai-toggle"
grep -q "omarchy-ai-setup" "$panel_dir/Panel.qml" || fail "panel switches modes with omarchy-ai-setup"
if grep -qE "omarchy-ai-(sync|logs)" "$panel_dir/Panel.qml"; then
  fail "the popup stays minimal — sync and logs live in the CLI"
fi
jq -e '.bar.layout.center | map(.id) | index("omarchy.local-ai")' \
  "$ROOT/config/omarchy/shell.json" >/dev/null || fail "default bar layout carries the local AI panel"
pass "the local AI panel is wired into the shell"
