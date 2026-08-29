#!/bin/bash
# Live GPU inventory. Sourced by omarchy-local-ai; do not run.
hardware_json() {
  [[ -n ${OMARCHY_AI_HARDWARE_JSON:-} ]] && { jq -c . <<<"$OMARCHY_AI_HARDWARE_JSON"; return; }
  local rows='' nvidia='[]'
  command -v nvidia-smi >/dev/null 2>&1 && rows=$(nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits 2>/dev/null || true)
  [[ -n $rows ]] && nvidia=$(jq -Rsc 'split("\n")|map(select(length>0)|split(",")|map(gsub("^ +| +$";"")))
    |map({backend:"nvidia",index:(.[0]|tonumber),product:.[1],totalMiB:(.[2]|tonumber),usedMiB:(.[3]|tonumber),freeMiB:(.[4]|tonumber)})
    |group_by(.product)|map({backend:"nvidia",product:.[0].product,count:length,memoryBytesEach:(.[0].totalMiB*1048576),
       devices:map({index,name:.product,totalMiB,usedMiB,freeMiB})})' <<<"$rows")
  jq -nc --argjson n "$nvidia" --argjson i "$(intel_arc_groups)" '{groups:($n+$i)}'
}
intel_arc_groups() {
  command -v lspci >/dev/null 2>&1 || { printf '[]'; return; }
  local dri="${OMARCHY_AI_DRI_PATH:-/dev/dri/by-path}" addrs devices='[]' idx=0 a node count
  addrs=$(lspci -Dnn 2>/dev/null | grep -i 'Arc Pro B70' | awk '{print $1}') || true
  while IFS= read -r a; do
    [[ -n $a ]] || continue
    node="$dri/pci-$a-render"
    [[ -e $node ]] || continue
    devices=$(jq -c --argjson idx "$idx" '.+[{index:$idx,name:"Intel Arc Pro B70",totalMiB:32768,usedMiB:null,freeMiB:null}]' <<<"$devices")
    idx=$((idx+1))
  done <<<"$addrs"
  count=$(jq 'length' <<<"$devices")
  (( count > 0 )) || { printf '[]'; return; }
  jq -nc --argjson d "$devices" --argjson c "$count" \
    '[{backend:"intel-xpu",product:"Intel Arc Pro B70",count:$c,memoryBytesEach:34359738368,devices:$d}]'
}
hardware_matched() {
  jq -c --slurpfile known <(jq -s '[.[]|{id,name,accelerator_backend,memory,aliases}]' "$REG"/hardware/*.json) '
    def norm: ascii_downcase|gsub("nvidia|geforce|intel|generation|workstation|edition|[0-9]+gb|[^a-z0-9]";"");
    .groups |= map(. as $g | ([$known[0][] | select(.accelerator_backend==$g.backend)
      | select((.name|norm)==($g.product|norm) or any(.aliases[]?; (.|norm)==($g.product|norm)))
      | select(((((.memory.vram_gb//0)*1024)-($g.memoryBytesEach/1048576))|fabs)<=1024)][0]) as $m
      | .+{registryId:($m.id//""),registryName:($m.name//"")})' <<<"$(hardware_json)"
}
gpus_json() { hardware_json | jq -c '[.groups[]| . as $g | .devices[]|{index,name,usedMiB,totalMiB,backend:$g.backend}]'; }
