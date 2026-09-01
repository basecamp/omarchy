#!/bin/bash
# Registry sync, recipe safety gate, catalog, and weight presence. Sourced; do not run.
reg_ok() { jq -e '.schema_version=="local-ai-registry/v1" and (.recipes|type=="array" and length>0)' "$IDX" >/dev/null 2>&1; }
reg_rev() { git -C "$REPO" rev-parse HEAD 2>/dev/null || printf ''; }
sync_registry() {
  [[ -n ${OMARCHY_AI_REGISTRY:-} ]] && { reg_ok || fail "registry invalid at $REG"; return; }
  if [[ ! -d $REPO/.git ]]; then git clone --filter=blob:none "$REMOTE" "$REPO" || { fail "registry clone failed"; return; }
  else
    [[ -z $(git -C "$REPO" status --porcelain) ]] || { fail "registry checkout has local changes"; return; }
    git -C "$REPO" fetch origin || { fail "registry fetch failed"; return; }
  fi
  if [[ -n $PIN ]]; then
    git -C "$REPO" -c advice.detachedHead=false checkout --quiet --detach "$PIN" \
      || { fail "pinned registry revision $PIN is unavailable"; return; }
  else
    git -C "$REPO" checkout --quiet main && git -C "$REPO" merge --ff-only --quiet origin/main \
      || { fail "registry update failed"; return; }
  fi
  reg_ok || fail "registry invalid at $REG"
}
resolve_raw() { # join recipe + instance + model + hardware + speed sweep; interpolate owned placeholders; no gate
  local id=$1 r i m h sid tps=0
  [[ -f $REG/recipe/$id.json ]] || { fail "unknown recipe $id"; return; }
  r=$(<"$REG/recipe/$id.json")
  i=$(<"$REG/model-instance/$(jq -r .model_instance_id <<<"$r").json")
  m=$(<"$REG/model/$(jq -r .model_id <<<"$i").json")
  h=$(<"$REG/hardware/$(jq -r .hardware_id <<<"$r").json")
  sid=$(jq -r '.speed_sweep_ids[0]//""' <<<"$r")
  [[ -n $sid && -f $REG/speed-sweep/$sid.json ]] && tps=$(jq -r \
    '[.metrics.peak_generation_tps,
      ([.rows[]?|select(.concurrency==1)|(.decode_tok_s//.decode_tok_s_per_stream)]|max),
      ([.rows[]?|(.decode_tok_s_per_stream//.decode_tok_s)]|max)]
     | map(select(.!=null)) | .[0] // 0' "$REG/speed-sweep/$sid.json")
  jq -nc --argjson r "$r" --argjson i "$i" --argjson m "$m" --argjson h "$h" --argjson tps "${tps:-0}" \
    --arg mr "$MODELS_SUB" --arg cr "$CACHE_SUB" '
    def arg($n): (.launch.arguments|index($n)) as $p | if $p==null then null else .launch.arguments[$p+1] end;
    {id:$r.id,status:$r.status,engine:$r.engine,capabilities:$r.capabilities,recommended:($r.recommended//false),
     serving:{ctxTokens:($r.serving.max_context_tokens//0),concurrency:($r.serving.max_concurrency//0)},
     speed:{tps:($tps|floor)},
     model:{id:$m.id,name:$m.name,repository:($i.repository//""),revision:($i.revision//""),
       servedName:(($r|arg("--served-model-name"))//$i.served_name//$i.repository),
       precision:($i.weights.precision//"?"),bytes:((($i.weights.size_gb//0)*1073741824)|floor)},
     hardware:{id:$h.id,name:$h.name,backend:$h.accelerator_backend,count:$r.hardware_count,vramGb:($h.memory.vram_gb//0)},
     launch:{image:($r.launch.image//""),containerPort:$r.launch.container_port,entrypoint:($r.launch.entrypoint//null),
       ipc:($r.launch.ipc//null),shm:($r.launch.shm_size//null),networkMode:($r.launch.network_mode//null),
       environment:($r.launch.environment//{}),
       arguments:($r.launch.arguments//[]),mounts:($r.launch.mounts//[]),devices:($r.launch.devices//[]),
       capAdd:($r.launch.cap_add//[]),securityOpt:($r.launch.security_opt//[])}}
    | .launch |= walk(if type=="string" then gsub("\\$\\{MODEL_ROOT\\}";$mr)|gsub("\\$\\{CACHE_ROOT\\}";$cr) else . end)'
}
gate_reason() { # gate_reason <resolved-json> -> one-line refusal reason on stdout; empty means launchable
  local r=$1 root src tgt ro reason primary=1 real plug_root hf_root
  root=$(cd "$REG" && pwd)
  plug_root=$(canon "$HOME_DIR/.cache/omarchy/local-ai")
  hf_root=$(canon "$HOME_DIR/.cache/huggingface")
  reason=$(jq -r '
    if .status!="validated" then "not validated"
    elif ((.launch.arguments|index("--nnodes"))!=null) then "runs across \(.launch.arguments[(.launch.arguments|index("--nnodes"))+1]//"several") networked machines"
    elif ([.launch|..|strings|select(test("\\$\\{"))]|length)>0 then "needs unsupported placeholder \([.launch|..|strings|select(test("\\$\\{"))]|first|capture("(?<p>\\$\\{[^}]+\\})").p)"
    elif ((.launch.networkMode//"bridge")!="bridge") then "requires \(.launch.networkMode) networking"
    elif ((.launch.ipc//"")=="host") then "requires host IPC"
    elif ((.launch.capAdd//[])|length)>0 then "requires extra kernel capabilities"
    elif ((.launch.securityOpt//[])|length)>0 then "requires a weakened security profile"
    elif (.launch.image|test("@sha256:[0-9a-f]{64}$")|not) then "image is not digest-pinned"
    elif (.model.revision|test("^[0-9a-f]{40,64}$")|not) then "model revision is not pinned"
    elif ((.launch.containerPort|type)!="number") then "invalid container port"
    elif ([.launch.arguments[]?|select(test("enforce.eager|disable.?cuda.?graph";"i"))]|length)>0 then "disallowed launch argument"
    else empty end' <<<"$r" 2>/dev/null) || { printf 'recipe data failed validation\n'; return; } # fail closed on malformed data
  [[ -z $reason ]] || { printf '%s\n' "$reason"; return; }
  while IFS=$'\t' read -r src tgt ro prepo prv; do
    case $src in
      "$MODELS_SUB"/*|"$CACHE_SUB"/*)
        [[ $src != *..* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        real=$(canon "$HOME_DIR/${src#\~/}")
        [[ $real == "$plug_root"/* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        if [[ $src == "$MODELS_SUB"/* && $ro != true ]]; then printf 'model weights must be mounted read-only\n'; return; fi
        if [[ $tgt == /model || $tgt == /models || $tgt == /workspace/models ]] && (( primary )); then primary=0
        elif [[ $ro == true && $src == "$MODELS_SUB"/* ]]; then
          if [[ -n $prepo ]]; then # provisioned: downloadable like the primary, but only from a pinned revision
            [[ $prv =~ ^[0-9a-f]{40,64}$ ]] || { printf 'provision for %s is not pinned\n' "$src"; return; }
          elif [[ ! -d $HOME_DIR/${src#\~/} ]]; then
            printf 'place weights at %s first\n' "$src"; return
          fi
        fi ;;
      \~/.cache/huggingface|\~/.cache/huggingface/*)
        [[ $src != *..* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        real=$(canon "$HOME_DIR/${src#\~/}")
        [[ $real == "$hf_root" || $real == "$hf_root"/* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; } ;;
      /dev/dri/by-path) ;;
      \~/*|/*) printf 'mounts unsafe host path %s\n' "$src"; return ;;
      *) src=$(cd "$root" && realpath "$src" 2>/dev/null) || { printf 'registry asset is missing\n'; return; }
         [[ $src == "$root/"* ]] || { printf 'asset escapes the registry\n'; return; } ;;
    esac
  done < <(jq -r '.launch.mounts[]?|[.source,.target,(.read_only//false|tostring),(.provision.repository//""),(.provision.revision//"")]|@tsv' <<<"$r")
}
provision_rows() { jq -r '.launch.mounts[]?|select(.provision.repository)|[.source,.provision.repository,(.provision.revision//""),(((.provision.size_gb//0)*1073741824)|floor)]|@tsv' <<<"$1"; }
dir_complete() { # dir_complete <dir> <expected-bytes>
  local d=$1 exp=$2 b
  [[ -d $d ]] || return 1
  has_incomplete "$d" && return 1
  b=$(dir_bytes "$d"); (( b > 0 )) || return 1
  (( exp == 0 )) && return 0
  (( b*100 >= exp*85 ))
}
resolve() {
  local id=$1 out reason
  out=$(resolve_raw "$id") || return 1
  reason=$(gate_reason "$out")
  [[ -z $reason ]] || { fail "recipe $id failed the safety gate: $reason"; return; }
  printf '%s\n' "$out"
}
resolve_mount() {
  local r=$1 src tgt
  while IFS=$'\t' read -r src tgt; do
    [[ $src == '~/.cache/huggingface' ]] && { printf 'hf\t%s\n' "$HOME_DIR/.cache/huggingface"; return; }
    [[ $src == '~/.cache/'* && ( $tgt == /model || $tgt == /models || $tgt == /workspace/models ) ]] && { printf 'dir\t%s\n' "$HOME_DIR/${src#\~/}"; return; }
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
provisions_have() {
  local r=$1 src prepo prv pexp
  while IFS=$'\t' read -r src prepo prv pexp; do
    dir_complete "$HOME_DIR/${src#\~/}" "$pexp" || return 1
  done < <(provision_rows "$r")
}
weights_have() { primary_have "$1" && provisions_have "$1"; }
primary_have() {
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
  local hw=$1 ids id r reason rows='[]' bytes pct ind img wt
  ids=$(jq -c '[.groups[].registryId|select(length>0)]' <<<"$hw")
  while IFS= read -r id; do
    r=$(resolve_raw "$id" 2>/dev/null) || continue
    [[ $(jq -r '.hardware.count' <<<"$r") == 1 ]] || continue # single-GPU recipes only for now
    reason=$(gate_reason "$r")
    if [[ -n $reason ]]; then
      rows=$(jq -c --argjson r "$r" --argjson hw "$hw" --arg reason "$reason" '
        ([$hw.groups[]|select(.registryId==$r.hardware.id)][0]) as $g
        | .+[{recipeId:$r.id,modelId:$r.model.id,name:$r.model.name,engine:$r.engine.name,
              precision:$r.model.precision,hardware:($g.registryName//$r.hardware.name),
              acceleratorCount:$r.hardware.count,available:false,
              imageDownloaded:false,weightsDownloaded:false,downloadPercent:0,downloadIndeterminate:true,
              sizeGb:((($r.model.bytes + (([$r.launch.mounts[]?.provision.size_gb//0]|add//0)*1073741824))/107374182|floor)/10),
              ctxTokens:$r.serving.ctxTokens,toksPerSec:$r.speed.tps,
              tools:($r.capabilities.tools//false),vision:($r.capabilities.vision//false),reasoning:($r.capabilities.reasoning//false),
              active:false,blocked:true,reason:$reason,recommended:false}]' <<<"$rows")
      continue
    fi
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
            sizeGb:((($r.model.bytes + (([$r.launch.mounts[]?.provision.size_gb//0]|add//0)*1073741824))/107374182|floor)/10),
            ctxTokens:$r.serving.ctxTokens,toksPerSec:$r.speed.tps,
            tools:($r.capabilities.tools//false),vision:($r.capabilities.vision//false),reasoning:($r.capabilities.reasoning//false),
            active:false,blocked:false,reason:"",recommended:($r.recommended//false)}]' <<<"$rows")
  done < <(jq -r --argjson ids "$ids" '.recipes[]|select(.status=="validated" and .launch_kind=="docker")
    |select(.hardware_id as $h|$ids|index($h))|.id' "$IDX")
  jq -c 'sort_by([.blocked,.acceleratorCount,(.weightsDownloaded|not),.name])' <<<"$rows"
}
