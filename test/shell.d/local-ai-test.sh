#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

plugin="$ROOT/shell/plugins/panels/local-ai"

[[ -x $plugin/bin/omarchy-local-ai ]] || fail "plugin controller is executable"
[[ -x $ROOT/bin/omarchy-local-ai ]] || fail "omarchy local-ai command is executable"
[[ -f $plugin/manifest.json ]] || fail "plugin manifest exists"

id=$(jq -r .id "$plugin/manifest.json")
[[ $id == "omarchy.local-ai" ]] || fail "plugin uses the first-party namespace" "$id"

bash "$plugin/test/all"

# Snapshot must stay read-only. ~/.cache/../.. must fail the safety gate.
home=$(mktemp -d)
state=$(mktemp -d)
reg=$(mktemp -d)
trap 'rm -rf "$home" "$state" "$reg"' EXIT
export OMARCHY_AI_USER_HOME="$home" OMARCHY_AI_STATE="$state" OMARCHY_AI_FOREGROUND=1
mkdir -p "$home/.pi/agent"
printf '%s\n' '{"theme":"dark"}' >"$home/.pi/agent/settings.json"
printf '%s\n' '{}' >"$home/.pi/agent/models.json"
OMARCHY_AI_HARDWARE_JSON='{"groups":[]}' "$plugin/bin/omarchy-local-ai" snapshot >/dev/null
[[ ! -d $home/.omp ]] || fail "snapshot must not create ~/.omp"
[[ $(jq -r '.defaultProvider // empty' "$home/.pi/agent/settings.json") == "" ]] || fail "snapshot must not set a default provider"
pass "snapshot does not write agent config"

mkdir -p "$reg"/{hardware,model,model-instance,recipe}
digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
jq -n '{schema_version:"local-ai-registry/v1",id:"rtx-3090-24gb",name:"GeForce RTX 3090",accelerator_backend:"nvidia",memory:{vram_gb:24},aliases:[]}' >"$reg/hardware/rtx-3090-24gb.json"
jq -n '{schema_version:"local-ai-registry/v1",id:"small",name:"Small"}' >"$reg/model/small.json"
jq -n --arg rev "$revision" '{schema_version:"local-ai-registry/v1",id:"org-small--bf16",model_id:"small",repository:"org/small",revision:$rev,served_name:"org/small",weights:{precision:"BF16",size_gb:0.0000001}}' >"$reg/model-instance/org-small--bf16.json"
jq -n --arg dg "$digest" '{id:"evil",status:"validated",model_instance_id:"org-small--bf16",hardware_id:"rtx-3090-24gb",hardware_count:1,engine:{name:"sglang"},capabilities:{tools:false},launch:{image:("img@sha256:"+$dg),container_port:30000,arguments:[],mounts:[{source:"~/.cache/../../../../etc",target:"/host-etc",read_only:false}]}}' >"$reg/recipe/evil.json"
jq -n '{schema_version:"local-ai-registry/v1",recipes:[{id:"evil",status:"validated",hardware_id:"rtx-3090-24gb",launch_kind:"docker"}]}' >"$reg/index.json"
export OMARCHY_AI_REGISTRY="$reg"
OMARCHY_AI_HARDWARE_JSON='{"groups":[{"backend":"nvidia","product":"NVIDIA GeForce RTX 3090","count":1,"memoryBytesEach":25769803776,"devices":[{"index":0,"name":"NVIDIA GeForce RTX 3090","totalMiB":24576,"usedMiB":0,"freeMiB":24576}]}]}' "$plugin/bin/omarchy-local-ai" download evil >/dev/null 2>"$state/evil.err" || true
jq -e '.state=="error" and (.error|test("validation|unsafe"))' >/dev/null <<<"$("$plugin/bin/omarchy-local-ai" snapshot)" || fail "traversing ~/.cache/../.. must fail the safety gate" "$(<"$state/evil.err")$("$plugin/bin/omarchy-local-ai" snapshot)"
pass "recipe mounts that traverse ~/.cache are refused"
