#!/bin/bash
# Labeled container launch, acceptance, and rollback. Sourced; do not run.
owned() { [[ $(docker inspect -f "{{index .Config.Labels \"$LABEL\"}}" "$1" 2>/dev/null) == 1 ]]; }
exists() { docker inspect "$1" >/dev/null 2>&1; }
running() { [[ $(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == true ]]; }
ts_bin() { command -v tailscale 2>/dev/null; }
share_state() { # -> {available,active,dns}; stateless, read from tailscale each time
  local b active=false dns=""
  b=$(ts_bin) || { printf '{"available":false,"active":false,"dns":""}\n'; return; }
  "$b" serve status 2>/dev/null | grep -q "127\.0\.0\.1:$PORT" && active=true
  dns=$("$b" status --json 2>/dev/null | jq -r '(.Self.DNSName//"")|rtrimstr(".")')
  jq -nc --argjson a "$active" --arg d "$dns" '{available:true,active:$a,dns:$d}'
}
share_on() { "$(ts_bin)" serve --bg --tcp "$PORT" "tcp://127.0.0.1:$PORT" >/dev/null; }
share_off() { local b; b=$(ts_bin) || return 0; "$b" serve --tcp "$PORT" off >/dev/null 2>&1 || true; }
gpu_ids() {
  hardware_json | jq -r --argjson need "$(jq -r .hardware.count <<<"$1")" \
    --arg id "$(jq -r .hardware.id <<<"$1")" --argjson hw "$(hardware_matched)" '
    [$hw.groups[]|select(.registryId==$id).product] as $p
    | [.groups[]|select(.product as $x|$p|index($x)).devices[]]|sort_by(-.freeMiB)|.[:$need]|map(.index)|join(",")'
}
build_argv() {
  local r=$1 root ids src tgt mode v backend root_real
  root_real=$(cd "$REG" && pwd)
  backend=$(jq -r .hardware.backend <<<"$r")
  local -a a=(docker run --detach --name "$CTR" --restart unless-stopped
    --label "$LABEL=1" --label "$LABEL.recipe=$(jq -r .id <<<"$r")")
  if [[ $backend == nvidia ]]; then
    ids=$(gpu_ids "$r"); [[ -n $ids ]] || { fail "no free matching GPUs"; return; }
    a+=(--gpus "device=$ids")
  else
    a+=(--device /dev/dri:/dev/dri)
  fi
  while IFS= read -r v; do [[ $backend != nvidia && $v == SYS_PTRACE ]] || { fail "unsupported capability $v"; return; }; a+=(--cap-add "$v"); done < <(jq -r '.launch.capAdd[]?' <<<"$r")
  while IFS= read -r v; do [[ $backend != nvidia && $v == seccomp=unconfined ]] || { fail "unsupported security option $v"; return; }; a+=(--security-opt "$v"); done < <(jq -r '.launch.securityOpt[]?' <<<"$r")
  a+=(--publish "127.0.0.1:$PORT:$(jq -r .launch.containerPort <<<"$r")")
  [[ $(jq -r '.launch.ipc//""' <<<"$r") == host ]] && a+=(--ipc host)
  v=$(jq -r '.launch.shm//empty' <<<"$r"); [[ -n $v ]] && a+=(--shm-size "$v")
  while IFS=$'\t' read -r src tgt mode; do
    [[ -n $src && -n $tgt ]] || continue
    if [[ $src == \~/* ]]; then [[ $src != *..* ]] || { fail "mount outside boundary: $src"; return; }; src=$HOME_DIR/${src#\~/}; mkdir -p "$src"
    elif [[ $src != /* ]]; then src=$(cd "$root_real" && realpath "$src") || { fail "mount missing"; return; }; fi
    [[ $src == "$HOME_DIR/.cache/"* || $src == /dev/dri/by-path || $src == "$root_real/"* ]] || { fail "mount outside boundary: $src"; return; }
    a+=(--volume "$src:$tgt$mode")
  done < <(jq -r '.launch.mounts[]?|[.source,.target,(if .read_only then ":ro" else "" end)]|@tsv' <<<"$r")
  while IFS= read -r v; do a+=(--env "$v"); done < <(jq -r '.launch.environment|to_entries[]?|"\(.key)=\(.value)"' <<<"$r")
  v=$(jq -r '.launch.entrypoint//empty' <<<"$r"); [[ -n $v ]] && a+=(--entrypoint "$v")
  a+=("$(jq -r .launch.image <<<"$r")")
  while IFS= read -r v; do a+=("$v"); done < <(jq -r '.launch.arguments[]?' <<<"$r")
  printf '%s\0' "${a[@]}"
}
api() { curl -fsS --max-time "${2:-30}" "http://127.0.0.1:$PORT/v1/$1"; }
post() { curl -fsS --max-time 600 -H 'Content-Type: application/json' -d "$2" "http://127.0.0.1:$PORT/v1/$1"; }
accept() {
  local r=$1 want served reply tools deadline=$((SECONDS+TIMEOUT))
  want=$(jq -r .model.servedName <<<"$r")
  while :; do
    served=$(api models 5 2>/dev/null | jq -r '.data[0].id // empty' || true)
    [[ -n $served ]] && break
    (( SECONDS < deadline )) || return 1
    running "$CTR" || return 1
    op starting "$(jq -r .id <<<"$r")" 0 true "waiting for /v1/models"
    sleep "$POLL"
  done
  [[ $served == "$want" || $want == */* && $served == *"${want##*/}"* ]] || return 1
  sw '.active.servedModel=$s | .active.apiReady=true' --arg s "$served"
  op starting "$(jq -r .id <<<"$r")" 0 true "chat acceptance"
  reply=$(post chat/completions "$(jq -nc --arg m "$served" '{model:$m,stream:false,messages:[{role:"user",content:"Reply with exactly: LOCAL_AI_READY"}]}')") || return 1
  jq -e '[(.choices[0].message.content//""),(.choices[0].message.reasoning_content//"")]|join(" ")|contains("LOCAL_AI_READY")' >/dev/null <<<"$reply" || return 1
  [[ $(jq -r '.capabilities.tools//false' <<<"$r") == true ]] || return 0
  op starting "$(jq -r .id <<<"$r")" 0 true "tool-call acceptance"
  tools='[{"type":"function","function":{"name":"shell","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}}]'
  reply=$(post chat/completions "$(jq -nc --arg m "$served" --argjson t "$tools" '{model:$m,stream:false,tools:$t,tool_choice:"auto",messages:[{role:"user",content:"Use the shell tool to run: echo LOCAL_AI_TOOL_OK"}]}')") || return 1
  jq -e '[(.choices[0].message.tool_calls//[])[]|select(.function.name=="shell" and ((.function.arguments//"")|contains("LOCAL_AI_TOOL_OK")))]|length>0' >/dev/null <<<"$reply" || return 1
  sw '.active.toolCallReady=true'
}
start_container() {
  local r=$1; local -a argv=()
  while IFS= read -r -d '' v; do argv+=("$v"); done < <(build_argv "$r") || return 1
  ((${#argv[@]})) || return 1
  "${argv[@]}" >/dev/null || return 1
  sw '.active={recipeId:$r.id,modelId:$r.model.id,name:$r.model.name,servedModel:"",container:$c,
       endpoint:("http://127.0.0.1:"+($p|tostring)+"/v1"),port:$p,gpuIndices:$ids,apiReady:false,
       toolCallReady:false,tools:($r.capabilities.tools//false),ctxTokens:$r.serving.ctxTokens,toksPerSec:$r.speed.tps}' \
    --argjson r "$r" --arg c "$CTR" --argjson p "$PORT" \
    --argjson ids "$(jq -Rsc 'rtrimstr("\n")|split(",")|map(select(length>0)|tonumber)' <<<"$(gpu_ids "$r" 2>/dev/null || true)")"
  accept "$r"
}
restore_previous() {
  exists "$PREV" || return 0
  owned "$PREV" || { fail "$PREV is not managed by this plugin"; return 0; }
  docker rename "$PREV" "$CTR" >/dev/null 2>&1 || true
  [[ $1 == true ]] && docker start "$CTR" >/dev/null 2>&1 || true
  return 0
}
