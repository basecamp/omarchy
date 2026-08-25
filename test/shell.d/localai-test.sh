#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

cat >"$tmp_dir/bin/curl" <<'SCRIPT'
#!/bin/bash
url=${!#}
case $url in
  *"/hardware/index.json")
    cat <<'JSON'
{"schemaVersion":"omarchy-local-ai/v1","hardware":[{"schemaVersion":"omarchy-local-ai/v1","id":"nvidia.rtx-3090.24gb.x2.pcie","aliases":["rtx-3090-24gb"],"vendor":"nvidia","product":"NVIDIA GeForce RTX 3090 24GB","acceleratorBackend":"nvidia","acceleratorCount":2,"memoryBytesEach":25769803776,"topology":{"kind":"pcie","description":"PCIe"},"platform":{"os":"linux","architecture":"x86_64"}},{"schemaVersion":"omarchy-local-ai/v1","id":"nvidia.rtx-3090.24gb.x4.pcie","aliases":["rtx-3090-24gb"],"vendor":"nvidia","product":"NVIDIA GeForce RTX 3090 24GB","acceleratorBackend":"nvidia","acceleratorCount":4,"memoryBytesEach":25769803776,"topology":{"kind":"pcie","description":"PCIe"},"platform":{"os":"linux","architecture":"x86_64"}}]}
JSON
    ;;
  *"/hardware/nvidia.rtx-3090.24gb.x4.pcie/recommendations/"*)
    cat <<'JSON'
{"schemaVersion":"omarchy-local-ai/v1","hardware":{"id":"nvidia.rtx-3090.24gb.x4.pcie"},"intent":"balanced","recommendations":[{"rank":1,"label":"Test Model","reason":"Validated.","recipeId":"test-recipe","model":{"id":"test","name":"Test Model","weights":"BF16"}}]}
JSON
    ;;
  *"/recipes/test-recipe.json")
    status=${MOCK_RECIPE_STATUS:-validated}
    cat <<JSON
{"schemaVersion":"omarchy-local-ai/v1","id":"test-recipe","status":"$status","compatibility":{"hardwareId":"nvidia.rtx-3090.24gb.x1.pcie","acceleratorBackend":"nvidia","acceleratorCount":1,"minimumMemoryBytesEach":21474836480},"model":{"repository":"org/model","revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","servedName":"model","weightPrecision":"BF16"},"engine":{"name":"sglang","version":"1"},"launch":{"adapter":"docker.openai-v1","image":"example/image@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","entrypoint":"/bin/server","arguments":["--model","org/model"],"environment":{"HF_HOME":"/models"},"sharedMemoryBytes":1073741824,"ipc":"host","modelCache":{"containerPath":"/models"}},"endpoint":{"containerPort":8000},"serving":{"measuredMaxContextTokens":131072}}
JSON
    ;;
  *) exit 22 ;;
esac
SCRIPT
chmod +x "$tmp_dir/bin/curl"

cat >"$tmp_dir/bin/nvidia-smi" <<'SCRIPT'
#!/bin/bash
cat <<'ROWS'
NVIDIA GeForce RTX 3090, 24576
NVIDIA GeForce RTX 3090, 24576
NVIDIA GeForce RTX 4090, 24576
ROWS
SCRIPT
chmod +x "$tmp_dir/bin/nvidia-smi"

export HOME="$tmp_dir/home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_LOCALAI_API=https://registry.test/v1
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"

run_localai() {
  "$BASH" "$ROOT/bin/omarchy-localai" "$@"
}

output=$(run_localai hardware --hardware nvidia.rtx-3090.24gb.x4.pcie)
[[ $output == *"4x NVIDIA GeForce RTX 3090"* ]] || fail "hardware override resolves exact API topology" "$output"
pass "hardware override resolves exact API topology"

output=$(run_localai hardware)
[[ $output == nvidia.rtx-3090.24gb.x2.pcie* ]] || fail "mixed GPUs resolve the largest homogeneous topology" "$output"
pass "mixed GPUs resolve the largest homogeneous topology"

output=$(run_localai list --hardware nvidia.rtx-3090.24gb.x4.pcie)
[[ $output == *"test-recipe"* ]] || fail "list prints API recommendation" "$output"
pass "list prints API recommendation"

output=$(run_localai run test-recipe --hardware nvidia.rtx-3090.24gb.x4.pcie --dry-run)
[[ $output == docker\ run* ]] || fail "dry run prints Docker argv" "$output"
[[ $output == *"--gpus 1"* ]] || fail "dry run uses recipe GPU count" "$output"
[[ $output == *"127.0.0.1:8000:8000"* ]] || fail "dry run binds API to loopback" "$output"
[[ $output == *"@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]] || fail "dry run keeps immutable image digest" "$output"
[[ ! -e $HOME/.cache ]] || fail "dry run creates no cache directory"
pass "dry run is side-effect free and immutable"

set +e
output=$(run_localai run test-recipe --hardware nvidia.rtx-3090.24gb.x4.pcie --gpus 0,1 --dry-run 2>&1)
result=$?
set -e
(( result == 2 )) || fail "GPU selection must match recipe topology" "$output"
[[ $output == *"Recipe needs 1 GPU(s)"* ]] || fail "GPU count refusal explains the mismatch" "$output"
pass "GPU selection must match recipe topology"

set +e
output=$(MOCK_RECIPE_STATUS=candidate run_localai run test-recipe --hardware nvidia.rtx-3090.24gb.x4.pcie --dry-run 2>&1)
result=$?
set -e
(( result == 2 )) || fail "candidate recipe is refused" "$output"
[[ $output == *"not launch-safe"* ]] || fail "candidate refusal explains the gate" "$output"
pass "candidate recipe is refused"
