#!/bin/bash
# Pi / Oh My Pi provider wiring and TUI launch. Sourced; do not run.
models_target() { # models_target <dir> -> the models config file this agent actually reads
  # Oh My Pi reads models.yml/models.yaml with precedence and treats models.json as a
  # one-time migration source, so ~/.omp gets YAML. JSON is valid YAML; we write JSON text.
  if [[ -f $1/models.yml ]]; then printf '%s/models.yml' "$1"
  elif [[ -f $1/models.yaml ]]; then printf '%s/models.yaml' "$1"
  elif [[ $1 == */.omp/* ]]; then printf '%s/models.yml' "$1"
  else printf '%s/models.json' "$1"; fi
}
wire() {
  local r=$1 model=$2 p d tgt cur tmp status
  p=$(jq -nc --arg u "http://127.0.0.1:$PORT/v1" --arg m "$model" --arg n "$(jq -r '.model.name//.model.id' <<<"$r")" \
    --argjson tools "$(jq -r '.capabilities.tools//false' <<<"$r")" \
    '{baseUrl:$u,apiKey:"local",api:"openai-completions",models:[{id:$m,name:($n+" · local"),supportsTools:$tools,input:["text"],cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}]}')
  for d in "$HOME_DIR/.pi/agent" "$HOME_DIR/.omp/agent"; do
    mkdir -p "$d"
    tgt=$(models_target "$d"); status=wired
    cur='{}'
    if [[ -f $tgt ]]; then cur=$(<"$tgt")
    elif [[ $tgt == *.yml && -f $d/models.json ]]; then cur=$(<"$d/models.json"); fi
    if jq -e 'type=="object"' >/dev/null 2>&1 <<<"$cur"; then
      tmp=$(mktemp "$d/.m.XXXXXX") && jq --argjson p "$p" '.providers["omarchy-local"]=$p' <<<"$cur" >"$tmp" && mv "$tmp" "$tgt"
    else
      status=manual # hand-written YAML we cannot merge; leave it alone and say so
    fi
    sw '.active.agents[$k]=$v' --arg k "$(basename "${d%/agent}" | tr -d .)" --arg v "$status"
    cur='{}'; [[ -f $d/settings.json ]] && cur=$(<"$d/settings.json")
    tmp=$(mktemp "$d/.s.XXXXXX") && jq --arg m "$model" 'if .defaultProvider=="omarchy-local" then .defaultModel=$m else . end' <<<"$cur" >"$tmp" && mv "$tmp" "$d/settings.json"
  done
  wire_json "$HOME_DIR/.config/opencode/opencode.json" opencode "$(jq -nc --arg u "http://127.0.0.1:$PORT/v1" --arg m "$model" \
    --arg n "$(jq -r '.model.name//.model.id' <<<"$r")" \
    '{npm:"@ai-sdk/openai-compatible",name:"Omarchy Local",options:{baseURL:$u},models:{($m):{name:($n+" · local")}}}')" '.provider["omarchy-local"]=$p'
  wire_json "$HOME_DIR/.config/crush/crush.json" crush "$(jq -nc --arg u "http://127.0.0.1:$PORT/v1" --arg m "$model" \
    --arg n "$(jq -r '.model.name//.model.id' <<<"$r")" \
    '{name:"Omarchy Local",type:"openai",base_url:$u,api_key:"local",models:[{id:$m,name:($n+" · local")}]}')" '.providers["omarchy-local"]=$p'
}
wire_json() { # wire_json <file> <agent-key> <provider-json> <jq-set-expr>: merge, never clobber unparseable configs
  local f=$1 key=$2 p=$3 expr=$4 cur='{}' tmp status=wired
  mkdir -p "$(dirname "$f")"
  [[ -f $f ]] && cur=$(<"$f")
  if jq -e 'type=="object"' >/dev/null 2>&1 <<<"$cur"; then
    tmp=$(mktemp "$(dirname "$f")/.w.XXXXXX") && jq --argjson p "$p" "$expr" <<<"$cur" >"$tmp" && mv "$tmp" "$f"
  else status=manual; fi
  sw '.active.agents[$k]=$v' --arg k "$key" --arg v "$status"
}
unwire() {
  local d f tmp
  for d in "$HOME_DIR/.pi/agent" "$HOME_DIR/.omp/agent"; do
    for f in "$d/models.json" "$d/models.yml" "$d/models.yaml"; do
      [[ -f $f ]] || continue
      jq -e 'type=="object"' "$f" >/dev/null 2>&1 || continue
      tmp=$(mktemp "$d/.m.XXXXXX") && jq 'del(.providers["omarchy-local"])' "$f" >"$tmp" && mv "$tmp" "$f"
    done
    [[ -f $d/settings.json ]] && tmp=$(mktemp "$d/.s.XXXXXX") && jq 'if .defaultProvider=="omarchy-local" then del(.defaultProvider,.defaultModel) else . end' "$d/settings.json" >"$tmp" && mv "$tmp" "$d/settings.json"
  done
  for f in "$HOME_DIR/.config/opencode/opencode.json" "$HOME_DIR/.config/crush/crush.json"; do
    [[ -f $f ]] || continue
    jq -e 'type=="object"' "$f" >/dev/null 2>&1 || continue
    tmp=$(mktemp "$(dirname "$f")/.w.XXXXXX") && jq 'del(.provider["omarchy-local"], .providers["omarchy-local"])' "$f" >"$tmp" && mv "$tmp" "$f"
  done
  return 0
}
set_default() { # make the running model the default for pi and omp
  local d tmp cur served
  [[ $(sread | jq -r '.active.apiReady') == true ]] || { fail "load a model first"; return; }
  served=$(sread | jq -r .active.servedModel)
  for d in "$HOME_DIR/.pi/agent" "$HOME_DIR/.omp/agent"; do
    mkdir -p "$d"
    cur='{}'; [[ -f $d/settings.json ]] && cur=$(<"$d/settings.json")
    jq -e 'type=="object"' >/dev/null 2>&1 <<<"$cur" || { fail "invalid $d/settings.json"; return; }
    tmp=$(mktemp "$d/.s.XXXXXX") && jq --arg m "$served" '.defaultProvider="omarchy-local" | .defaultModel=$m' <<<"$cur" >"$tmp" && mv "$tmp" "$d/settings.json"
  done
}
launch_tui() {
  local cmd enc rt sig
  printf -v cmd '%q ' omarchy-launch-tui --app-id=org.omarchy.agent "$@"
  enc=$(jq -Rn --arg c "$cmd" '$c'); rt=${XDG_RUNTIME_DIR:-/run/user/$UID}; sig=${HYPRLAND_INSTANCE_SIGNATURE:-}
  [[ -n $sig && -d $rt/hypr/$sig ]] || sig=$(ls -t "$rt/hypr" 2>/dev/null | head -1)
  [[ -n $sig ]] || fail "Hyprland session not found"
  HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl dispatch "hl.dsp.exec_cmd($enc)" >/dev/null
}
agents_scan() { # -> {default,installed}: Omarchy's default agent and which known agents exist
  local a list='[]' def=""
  for a in pi omp opencode ori claude codex grok agy copilot crush; do
    bin_of "$a" >/dev/null 2>&1 && list=$(jq -c --arg a "$a" '.+[$a]' <<<"$list")
  done
  command -v omarchy-default-agent >/dev/null 2>&1 && def=$(omarchy-default-agent 2>/dev/null || true)
  jq -nc --arg d "${def:-}" --argjson i "$list" '{default:$d,installed:$i}'
}
open_agent() { # no argument: Omarchy's default agent; pi/omp get the local model wired in explicitly
  local name=${1:-} bin served sid; sid=${OMARCHY_AI_SESSION_ID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr A-Z a-z)}
  [[ $(sread | jq -r '.active.apiReady') == true ]] || fail "load a model first"
  [[ -n $name ]] || { name=$(command -v omarchy-default-agent >/dev/null 2>&1 && omarchy-default-agent 2>/dev/null || true); name=${name:-pi}; }
  served=$(sread | jq -r .active.servedModel)
  case $name in
    pi) bin=$(bin_of pi) || fail "pi is not installed"
        launch_tui "$bin" --provider omarchy-local --model "$served" --session-id "$sid" ;;
    omp) bin=$(bin_of omp) || fail "omp is not installed"
         launch_tui "$bin" --provider omarchy-local --model "$served" --session-id "$sid" ;;
    opencode) bin=$(bin_of opencode) || fail "opencode is not installed"
         launch_tui "$bin" --model "omarchy-local/$served" ;;
    *) launch_tui omarchy-agent ;; # their chosen agent, launched the way Omarchy launches it
  esac
}
