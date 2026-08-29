#!/bin/bash
# Registry sync, recipe safety gate, catalog, and weight presence. Sourced; do not run.
reg_ok() { jq -e '.schema_version=="local-ai-registry/v1" and (.recipes|type=="array" and length>0)' "$REG/index.json" >/dev/null 2>&1; }
sync_registry() {
  [[ -n ${OMARCHY_AI_REGISTRY:-} ]] && { reg_ok || fail "registry invalid at $REG"; return; }
  if [[ ! -d $REPO/.git ]]; then git clone --filter=blob:none --branch main "$REMOTE" "$REPO"
  else
    [[ -z $(git -C "$REPO" status --porcelain) ]] || fail "registry checkout has local changes"
    git -C "$REPO" fetch origin main && git -C "$REPO" merge --ff-only origin/main
  fi
  reg_ok || fail "registry invalid at $REG"
}
resolve() {
  local id=$1 r i m h out src root; root=$(cd "$REG" && pwd)
  [[ -f $REG/recipe/$id.json ]] || { fail "unknown recipe $id"; return; }
  r=$(<"$REG/recipe/$id.json")
  i=$(<"$REG/model-instance/$(jq -r .model_instance_id <<<"$r").json")
  m=$(<"$REG/model/$(jq -r .model_id <<<"$i").json")
  h=$(<"$REG/hardware/$(jq -r .hardware_id <<<"$r").json")
  out=$(jq -nc --argjson r "$r" --argjson i "$i" --argjson m "$m" --argjson h "$h" '
    def arg($n): (.launch.arguments|index($n)) as $p | if $p==null then null else .launch.arguments[$p+1] end;
    {id:$r.id,status:$r.status,engine:$r.engine,capabilities:$r.capabilities,
     model:{id:$m.id,name:$m.name,repository:$i.repository,revision:$i.revision,
       servedName:(($r|arg("--served-model-name"))//$i.served_name//$i.repository),
       precision:($i.weights.precision//"?"),bytes:((($i.weights.size_gb//0)*1073741824)|floor)},
     hardware:{id:$h.id,name:$h.name,backend:$h.accelerator_backend,count:$r.hardware_count,vramGb:($h.memory.vram_gb//0)},
     launch:{image:$r.launch.image,containerPort:$r.launch.container_port,entrypoint:($r.launch.entrypoint//null),
       ipc:($r.launch.ipc//null),shm:($r.launch.shm_size//null),environment:($r.launch.environment//{}),
       arguments:($r.launch.arguments//[]),mounts:($r.launch.mounts//[]),devices:($r.launch.devices//[]),
       capAdd:($r.launch.cap_add//[]),securityOpt:($r.launch.security_opt//[])}}' | jq -ce '
    select(.status=="validated")
    | select(.launch.image|test("@sha256:[0-9a-f]{64}$"))
    | select(.model.revision|test("^[0-9a-f]{40,64}$"))
    | select(.launch.containerPort|type=="number")
    | select([.launch.arguments[]?|select(test("enforce.eager|disable.?cuda.?graph";"i"))]|length==0)') \
    || { fail "recipe $id failed the safety gate"; return; }
  while IFS= read -r src; do
    case $src in
      \~/.cache/*) [[ $src != *..* ]] || { fail "recipe $id mounts unsafe host path $src"; return; } ;;
      /dev/dri/by-path) ;;
      /*) fail "recipe $id mounts unsafe host path $src"; return ;;
      *) src=$(cd "$root" && realpath "$src" 2>/dev/null) || { fail "recipe $id asset missing"; return; }
         [[ $src == "$root/"* ]] || { fail "recipe $id asset escapes the registry"; return; } ;;
    esac
  done < <(jq -r '.launch.mounts[]?.source' <<<"$out")
  printf '%s\n' "$out"
}
resolve_mount() {
  local r=$1 src tgt
  while IFS=$'\t' read -r src tgt; do
    [[ $src == '~/.cache/huggingface' ]] && { printf 'hf\t%s\n' "$HOME_DIR/.cache/huggingface"; return; }
    [[ $src == '~/.cache/'* && ( $tgt == /models || $tgt == /workspace/models ) ]] && { printf 'dir\t%s\n' "$HOME_DIR/${src#\~/}"; return; }
  done < <(jq -r '.launch.mounts[]?|[.source,.target]|@tsv' <<<"$r")
  printf 'hf\t%s\n' "$HOME_DIR/.cache/huggingface"
}
hf_cache_dir() { printf '%s/hub/models--%s\n' "$1" "${2//\//--}"; }
dir_bytes() { [[ -d $1 ]] && du -skL "$1" 2>/dev/null | awk '{print $1*1024}' || printf 0; }
has_incomplete() { find "$1" -name '*.incomplete' 2>/dev/null -print -quit | grep -q .; }
progress_bytes() {
  local r=$1 kind base; read -r kind base < <(resolve_mount "$r")
  if [[ $kind == hf ]]; then dir_bytes "$(hf_cache_dir "$base" "$(jq -r .model.repository <<<"$r")")/snapshots/$(jq -r .model.revision <<<"$r")"
  else dir_bytes "$base"; fi
}
image_have() { docker image inspect "$1" >/dev/null 2>&1; }
hf_bin() { [[ -z ${OMARCHY_AI_NO_HOST_HF:-} ]] && bin_of hf 2>/dev/null; return 0; }
weights_have() {
  local r=$1 repo rev exp kind base d b file
  repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r"); exp=$(jq -r .model.bytes <<<"$r")
  read -r kind base < <(resolve_mount "$r")
  if [[ $kind == hf ]]; then
    d=$(hf_cache_dir "$base" "$repo")/snapshots/$rev
    [[ -d $d ]] || return 1
    has_incomplete "$d" && return 1
    b=$(dir_bytes "$d"); (( b > 0 )) || return 1
    (( exp == 0 )) && return 0
    (( b*100 >= exp*85 )); return
  fi
  file=$(jq -r .model.servedName <<<"$r")
  if [[ $file == *.gguf && -f "$base/${file##*/}" ]]; then
    b=$(stat -c%s "$base/${file##*/}" 2>/dev/null || stat -f%z "$base/${file##*/}" 2>/dev/null || printf 0)
    (( exp == 0 )) && return 0
    (( b*100 >= exp*85 )); return
  fi
  [[ -d $base ]] || return 1
  has_incomplete "$base" && return 1
  b=$(dir_bytes "$base"); (( b > 0 )) || return 1
  (( exp == 0 )) && return 0
  (( b*100 >= exp*85 ))
}
catalog() {
  local hw=$1 ids id r rows='[]' bytes pct ind img wt
  ids=$(jq -c '[.groups[].registryId|select(length>0)]' <<<"$hw")
  while IFS= read -r id; do
    r=$(resolve "$id" 2>/dev/null) || continue
    bytes=$(progress_bytes "$r")
    ind=true; pct=0
    if (( $(jq -r .model.bytes <<<"$r") > 0 )); then
      ind=false; pct=$(jq -r --argjson b "$bytes" '[($b*100/.model.bytes)|floor,100]|min' <<<"$r")
    fi
    img=false; image_have "$(jq -r .launch.image <<<"$r")" && img=true
    wt=false; weights_have "$r" && wt=true
    rows=$(jq -c --argjson r "$r" --argjson hw "$hw" --argjson img "$img" --argjson wt "$wt" \
      --argjson pct "$pct" --argjson ind "$ind" '
      ([$hw.groups[]|select(.registryId==$r.hardware.id)][0]) as $g
      | .+[{recipeId:$r.id,modelId:$r.model.id,name:$r.model.name,engine:$r.engine.name,
            precision:$r.model.precision,hardware:($g.registryName//$r.hardware.name),
            acceleratorCount:$r.hardware.count,available:(($g.count//0)>=$r.hardware.count),
            imageDownloaded:$img,weightsDownloaded:$wt,downloadPercent:$pct,downloadIndeterminate:$ind,
            tools:($r.capabilities.tools//false),active:false}]' <<<"$rows")
  done < <(jq -r --argjson ids "$ids" '.recipes[]|select(.status=="validated" and .launch_kind=="docker")
    |select(.hardware_id as $h|$ids|index($h))|.id' "$REG/index.json")
  jq -c 'sort_by([.acceleratorCount,(.weightsDownloaded|not),.name])' <<<"$rows"
}
