#!/bin/bash
# Scan / download / run / switch / unload workers. Sourced; do not run.
w_scan() {
  guard || oops "another operation is running"
  sync_registry >/dev/null 2>&1 || oops "registry sync failed"
  local hw models total
  hw=$(hardware_matched) || oops "hardware scan failed"
  models=$(catalog "$hw")
  total=$(jq '.recipes|length' "$REG/index.json")
  sw '.hardware=$h | .models=$m | .gpus=$g | .registry={path:$p,matching:($m|length),total:$t}
      | .models|=map(.active=(.recipeId==($ss.active.recipeId//"")))
      | .state=(if ($ss.active.apiReady//false) then "ready" else "idle" end)
      | .operation={name:"",recipeId:"",percent:0,indeterminate:false,detail:""} | .error=""' \
    --argjson h "$hw" --argjson m "$models" --argjson g "$(gpus_json)" --arg p "$REG" \
    --argjson t "$total" --argjson ss "$(sread)"
  trace "$(sread | jq -r .state)"
}
w_download() {
  local id=$1 r img repo rev exp kind base hf file bytes pct pid
  guard || oops "another operation is running"
  r=$(resolve "$id") || oops "recipe $id failed validation"
  img=$(jq -r .launch.image <<<"$r"); repo=$(jq -r .model.repository <<<"$r")
  rev=$(jq -r .model.revision <<<"$r"); exp=$(jq -r .model.bytes <<<"$r")
  op download "$id" 0 true "pulling image"
  image_have "$img" || docker pull "$img" >/dev/null 2>&1 || oops "image pull failed for $id"
  if weights_have "$r"; then op download "$id" 100 false "weights present"
  else
    read -r kind base < <(resolve_mount "$r"); mkdir -p "$base"
    hf=$(hf_bin || true)
    file=$(jq -r .model.servedName <<<"$r"); local -a extra=()
    [[ $kind == dir && $file == *.gguf ]] && extra=("${file##*/}")
    if [[ $kind == hf ]]; then
      if [[ -n $hf ]]; then "$hf" download "$repo" --revision "$rev" >/dev/null 2>&1 & pid=$!
      else docker run --rm --user "$(id -u):$(id -g)" --label "$LABEL.download=1" --entrypoint hf --volume "$base:/root/.cache/huggingface" "$img" download "$repo" --revision "$rev" >/dev/null 2>&1 & pid=$!; fi
    else
      if [[ -n $hf ]]; then "$hf" download "$repo" "${extra[@]}" --revision "$rev" --local-dir "$base" >/dev/null 2>&1 & pid=$!
      else docker run --rm --user "$(id -u):$(id -g)" --label "$LABEL.download=1" --entrypoint hf --volume "$base:$base" "$img" download "$repo" "${extra[@]}" --revision "$rev" --local-dir "$base" >/dev/null 2>&1 & pid=$!; fi
    fi
    while kill -0 "$pid" 2>/dev/null; do
      bytes=$(progress_bytes "$r")
      if (( exp > 0 )); then pct=$(( bytes*100/exp )); (( pct > 100 )) && pct=100
        op download "$id" "$pct" false "$((bytes/1073741824)) / $((exp/1073741824)) GB"
      else op download "$id" 0 true "downloading weights"; fi
      sleep "$POLL"
    done
    wait "$pid" || oops "weight download failed for $id"
    weights_have "$r" || oops "download incomplete for $id"
    op download "$id" 100 false "weights complete"
  fi
  w_refresh_models
  [[ $(sread | jq -r '.active.apiReady') == true ]] && setstate ready || setstate downloaded
}
w_refresh_models() {
  local hw; hw=$(sread | jq -c '.hardware')
  [[ $(jq '.groups|length' <<<"$hw") -gt 0 ]] || hw=$(hardware_matched)
  sw '.models=$m | .gpus=$g | .models|=map(.active=(.recipeId==$a))' \
    --argjson m "$(catalog "$hw")" --argjson g "$(gpus_json)" --arg a "$(sread | jq -r .active.recipeId)"
}
w_run() {
  local id=$1 phase=$2 r was=false prev_active
  guard || oops "another operation is running"
  r=$(resolve "$id") || oops "recipe $id failed validation"
  jq -e --arg i "$id" '.models[]|select(.recipeId==$i and .imageDownloaded and .weightsDownloaded)' >/dev/null <<<"$(sread)" \
    || oops "model $id is not downloaded"
  prev_active=$(sread | jq -c .active)
  op "$phase" "$id" 0 true "preparing container"
  if exists "$CTR"; then
    owned "$CTR" || oops "$CTR exists but is not managed by this plugin"
    if exists "$PREV"; then owned "$PREV" || oops "$PREV exists but is not managed by this plugin"; fi
    running "$CTR" && was=true && docker stop "$CTR" >/dev/null 2>&1
    if exists "$PREV"; then docker rm -f "$PREV" >/dev/null 2>&1; fi
    docker rename "$CTR" "$PREV" >/dev/null || oops "could not set aside the running container"
  fi
  op "$phase" "$id" 0 true "starting container"
  if ! start_container "$r" || ! wire "$r" "$(sread | jq -r .active.servedModel)"; then
    owned "$CTR" && docker rm -f "$CTR" >/dev/null 2>&1 || true
    op "$phase" "$id" 0 true "rolling back"
    restore_previous "$was"
    sw '.active=$a' --argjson a "$prev_active"
    w_refresh_models
    oops "$id failed acceptance; previous model restored"
  fi
  if exists "$PREV" && owned "$PREV"; then docker rm -f "$PREV" >/dev/null 2>&1; fi
  w_refresh_models
  op "" "$id" 100 false ""
  setstate ready
}
w_unload() {
  guard || oops "another operation is running"
  op unload "" 0 true "stopping container"
  if exists "$CTR"; then
    owned "$CTR" || oops "$CTR is not managed by this plugin"
    docker rm -f "$CTR" >/dev/null 2>&1 || true
  fi
  if exists "$PREV" && owned "$PREV"; then docker rm -f "$PREV" >/dev/null 2>&1; fi
  unwire
  sw '.active=$e.active | .models|=map(.active=false)' --argjson e "$EMPTY"
  w_refresh_models
  op "" "" 0 false ""
  setstate idle
}
emit() {
  local s g served ok=false; adopt; s=$(sread)
  if jq -e '. as $s|$s.active.apiReady and (["scanning","downloading","starting","switching","unloading"]|index($s.state)|not)' >/dev/null <<<"$s"; then
    g=$(gpus_json 2>/dev/null || printf '[]'); owned "$CTR" && running "$CTR" && served=$(api models 2 2>/dev/null | jq -r '.data[0].id//empty') && [[ $served == "$(jq -r .active.servedModel <<<"$s")" ]] && ok=true
    $ok && jq -c --argjson g "$g" '.gpus=$g' <<<"$s" || jq -c --argjson g "$g" '.gpus=$g|.state="error"|.error=(if .error=="" then "accepted runtime is unavailable" else .error end)|.active.apiReady=false|.active.toolCallReady=false' <<<"$s"
  else printf '%s\n' "$s"; fi
}
adopt() {
  local s state rid r served ids; s=$(sread); state=$(jq -r .state <<<"$s"); [[ $(jq -r '.active.container' <<<"$s") == "" && $state =~ ^(uninitialized|idle|downloaded|error)$ ]] || return 0
  owned "$CTR" && running "$CTR" || return 0; rid=$(docker inspect -f "{{index .Config.Labels \"$LABEL.recipe\"}}" "$CTR" 2>/dev/null) || return 0
  r=$(resolve "$rid" 2>/dev/null) || return 0; served=$(api models 2 2>/dev/null | jq -r '.data[0].id//empty') || return 0; [[ -n $served ]] || return 0
  ids=$(docker inspect -f '{{json .HostConfig.DeviceRequests}}' "$CTR" 2>/dev/null | jq -c '[.[]?.DeviceIDs[]?|tonumber]' 2>/dev/null || printf '[]'); [[ -n $ids ]] || ids='[]'
  sw '.active={recipeId:$r.id,modelId:$r.model.id,name:$r.model.name,servedModel:$s,container:$c,endpoint:("http://127.0.0.1:"+($p|tostring)+"/v1"),port:$p,gpuIndices:$ids,apiReady:true,toolCallReady:false,tools:($r.capabilities.tools//false)}|.models|=map(.active=(.recipeId==$r.id))|.state="ready"|.error=""' --argjson r "$r" --arg s "$served" --arg c "$CTR" --argjson p "$PORT" --argjson ids "$ids"
}
