set -euo pipefail

AI_STATE_DIR="$HOME/.local/state/omarchy/local-ai"
AI_STATE_FILE="$AI_STATE_DIR/recipe.json"
AI_CONTAINER="${OMARCHY_AI_CONTAINER:-omarchy-local-ai}"

ai_catalog_path() {
  if [[ -n ${OMARCHY_AI_CATALOG:-} ]]; then
    printf '%s\n' "$OMARCHY_AI_CATALOG"
  elif [[ -f $AI_STATE_DIR/catalog.json ]]; then
    printf '%s\n' "$AI_STATE_DIR/catalog.json"
  else
    printf '%s\n' "$OMARCHY_PATH/default/omarchy/local-ai.json"
  fi
}

ai_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

ai_hardware_json() {
  local backend="${1:-nvidia}"
  if [[ -n ${OMARCHY_AI_HARDWARE_JSON:-} ]]; then
    jq . <<<"$OMARCHY_AI_HARDWARE_JSON"
    return
  fi

  local devices="[]"
  local rows=""
  local query="index,name,uuid,memory.total,memory.free,compute_cap"
  local selector=()
  if [[ -n ${OMARCHY_AI_GPUS:-} ]]; then
    selector=(-i "$OMARCHY_AI_GPUS")
  fi

  if [[ $backend == "intel-xpu" ]] && command -v lspci >/dev/null 2>&1; then
    local intel_index=0
    while IFS= read -r row; do
      [[ $row == *"Intel Corporation Battlemage G31 [Arc Pro B70]"* ]] || continue
      devices=$(jq --argjson index "$intel_index" '. + [{index: $index, name: "Intel Arc Pro B70", uuid: null, total_vram_mb: 32768, free_vram_mb: 32768, compute_capability: null, vendor: "intel"}]' <<<"$devices")
      ((intel_index += 1))
    done < <(lspci -Dnn 2>/dev/null || true)
  elif command -v nvidia-smi >/dev/null 2>&1; then
    rows=$(nvidia-smi "${selector[@]}" --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null || true)
    if [[ -z $rows ]]; then
      query="index,name,uuid,memory.total,memory.free"
      rows=$(nvidia-smi "${selector[@]}" --query-gpu="$query" --format=csv,noheader,nounits 2>/dev/null || true)
    fi
  fi

  local index="" name="" uuid="" total="" free="" compute=""
  while IFS=',' read -r index name uuid total free compute; do
    index=$(ai_trim "$index")
    name=$(ai_trim "$name")
    uuid=$(ai_trim "$uuid")
    total=$(ai_trim "$total")
    free=$(ai_trim "$free")
    compute=$(ai_trim "${compute:-}")
    [[ $index =~ ^[0-9]+$ && $total =~ ^[0-9]+$ && $free =~ ^[0-9]+$ ]] || continue
    devices=$(jq --argjson index "$index" --arg name "$name" --arg uuid "$uuid" --argjson total "$total" --argjson free "$free" --arg compute "$compute" '. + [{index: $index, name: $name, uuid: $uuid, total_vram_mb: $total, free_vram_mb: $free, compute_capability: (if $compute == "" then null else $compute end), vendor: "nvidia"}]' <<<"$devices")
  done <<<"$rows"

  local count family family_id hardware_id total_vram free_vram disk_kb runtime_installed runtime_ready runtime_version nvidia_runtime
  count=$(jq 'length' <<<"$devices")
  family=$(jq -r '.[0].name // "unsupported"' <<<"$devices" | tr '[:upper:]' '[:lower:]' | sed -E 's/^nvidia //; s/^geforce //; s/^intel //; s/[^a-z0-9]+/-/g; s/^-|-$//g')
  family_id="$family"
  total_vram=$(jq '[.[].total_vram_mb] | add // 0' <<<"$devices")
  free_vram=$(jq '[.[].free_vram_mb] | add // 0' <<<"$devices")
  if ((count > 0)); then
    local per_device_gb
    per_device_gb=$(( $(jq -r '.[0].total_vram_mb' <<<"$devices") / 1024 ))
    hardware_id="${family_id}-${per_device_gb}gb"
    if ((count > 1)); then
      hardware_id+="-x$count"
    fi
  else
    hardware_id="unsupported"
  fi

  runtime_installed=false
  runtime_ready=false
  runtime_version=""
  nvidia_runtime=false
  if command -v docker >/dev/null 2>&1; then
    runtime_installed=true
    runtime_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
    if [[ -n $runtime_version ]]; then
      runtime_ready=true
      if docker info --format '{{json .Runtimes}}' 2>/dev/null | jq -e 'has("nvidia")' >/dev/null 2>&1; then
        nvidia_runtime=true
      fi
    fi
  fi
  disk_kb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print $4}' || printf '0')
  [[ $disk_kb =~ ^[0-9]+$ ]] || disk_kb=0

  jq -n --arg hardware_id "$hardware_id" --arg family_id "$family_id" --arg backend "$backend" --argjson devices "$devices" --argjson total "$total_vram" --argjson free "$free_vram" --argjson installed "$runtime_installed" --argjson ready "$runtime_ready" --arg version "$runtime_version" --argjson nvidia "$nvidia_runtime" --argjson disk "$((disk_kb * 1024))" '{schema_version: 1, hardware_id: $hardware_id, family_id: $family_id, vendor: (if ($devices | length) > 0 then $devices[0].vendor else "unsupported" end), accelerator_backend: $backend, devices: $devices, total_vram_mb: $total, free_vram_mb: $free, runtime: {name: "docker", installed: $installed, ready: $ready, version: $version, nvidia: $nvidia}, disk_free_bytes: $disk}'
}

ai_error_json() {
  jq -n --arg code "$1" --arg message "$2" '{ok: false, error: {code: $code, message: $message}}'
}

ai_port_available() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    [[ -z $(ss -H -ltn "sport = :$port" 2>/dev/null) ]]
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 1
    else
      return 0
    fi
  else
    return 0
  fi
}

ai_resolve_json() {
  local wanted="${1:-}"
  local hardware catalog devices recipe backend qualifying step resolved gpu_count available_count selected available reason
  catalog=$(ai_catalog_path)
  if [[ ! -f $catalog ]]; then
    ai_error_json "NO_CATALOG" "No local recipe catalog was found"
    return
  fi

  if [[ -n $wanted ]]; then
    recipe=$(jq --arg name "$wanted" 'first(.recipes[] | select(.name == $name)) // empty' "$catalog")
    if [[ -z $recipe ]]; then
      ai_error_json "UNKNOWN_RECIPE" "No recipe named $wanted"
      return
    fi
  else
    recipe=$(jq '[.recipes[] | select((.status // "candidate") == "validated") | select((.accelerator_backend // "nvidia") == "nvidia")] | sort_by([-.min_vram_mb, -(.min_gpus // 1), .name]) | first // empty' "$catalog")
    if [[ -z $recipe ]]; then
      ai_error_json "NO_COMPATIBLE_RECIPE" "No recipe in the local catalog fits this hardware"
      return
    fi
  fi

  backend=$(jq -r '.accelerator_backend // "nvidia"' <<<"$recipe")
  hardware=$(ai_hardware_json "$backend")
  devices=$(jq '.devices' <<<"$hardware")
  if [[ $(jq 'length' <<<"$devices") == 0 ]]; then
    ai_error_json "NO_SUPPORTED_GPU" "No GPU for backend $backend was detected"
    return
  fi
  if ! jq --argjson devices "$devices" -e '. as $recipe | (([$devices[] | select(.total_vram_mb >= $recipe.min_vram_mb)] | length) >= ($recipe.min_gpus // 1))' <<<"$recipe" >/dev/null; then
    ai_error_json "INCOMPATIBLE_HARDWARE" "Recipe $wanted does not fit this hardware"
    return
  fi

  qualifying=$(jq --argjson devices "$devices" '. as $recipe | [$devices[] | select(.total_vram_mb >= $recipe.min_vram_mb)] | length' <<<"$recipe")
  step=$(jq --argjson count "$qualifying" '(.scale // {} | to_entries | map(select((.key | tonumber) <= $count)) | sort_by(.key | tonumber) | last) // null' <<<"$recipe")
  gpu_count=$(jq --argjson step "$step" 'if $step == null then (.min_gpus // 1) else ($step.key | tonumber) end' <<<"$recipe")
  resolved=$(jq --argjson step "$step" --argjson count "$gpu_count" 'if $step == null then del(.scale) + {gpu_count: $count} else (del(.scale) * $step.value) + {gpu_count: $count} end' <<<"$recipe")
  available_count=$(jq --argjson recipe "$resolved" '[.[] | select(.free_vram_mb >= $recipe.min_vram_mb)] | length' <<<"$devices")
  selected=$(jq --argjson recipe "$resolved" --argjson count "$gpu_count" '(([.[] | select(.free_vram_mb >= $recipe.min_vram_mb)] | sort_by(.index)) + ([.[] | select(.free_vram_mb < $recipe.min_vram_mb and .total_vram_mb >= $recipe.min_vram_mb)] | sort_by(.index))) | .[:$count] | map(.index)' <<<"$devices")
  available=false
  reason="needs $gpu_count GPU(s) with at least $(jq -r '.min_vram_mb' <<<"$resolved") MB free each"
  if ((available_count >= gpu_count)); then
    available=true
    reason="ready"
  fi

  jq -n --argjson hardware "$hardware" --argjson recipe "$resolved" --argjson selected "$selected" --argjson available "$available" --arg reason "$reason" --arg catalog "$catalog" '{ok: true, hardware: $hardware, recipe: $recipe, selected_device_ids: $selected, availability: {available: $available, reason: $reason}, catalog: $catalog}'
}

ai_plan_json() {
  local wanted="${1:-}"
  local port="${2:-}"
  local resolution recipe selected ids image container_port network_mode pair source target argv_json port_available
  resolution=$(ai_resolve_json "$wanted")
  if [[ $(jq -r '.ok' <<<"$resolution") != "true" ]]; then
    jq . <<<"$resolution"
    return
  fi

  recipe=$(jq '.recipe' <<<"$resolution")
  selected=$(jq '.selected_device_ids' <<<"$resolution")
  ids=$(jq -r 'map(tostring) | join(",")' <<<"$selected")
  if [[ -z $port ]]; then
    port=$(jq -r '.host_port // empty' <<<"$recipe")
  fi
  if [[ -z $port ]]; then
    port=$(jq -r '.port' "$(ai_catalog_path)")
  fi
  port_available=false
  if ai_port_available "$port"; then
    port_available=true
  fi
  container_port=$(jq -r '.container_port // 8000' <<<"$recipe")
  network_mode=$(jq -r '.network_mode // empty' <<<"$recipe")
  image=$(jq -r '.image' <<<"$recipe")

  local backend
  backend=$(jq -r '.accelerator_backend // "nvidia"' <<<"$recipe")
  local docker_args=(docker run --detach --name "$AI_CONTAINER" --label io.omarchy.local-ai=1 --label "io.omarchy.local-ai.recipe=$(jq -r '.name' <<<"$recipe")" --restart unless-stopped)
  if [[ $backend == "intel-xpu" ]]; then
    docker_args+=(--device /dev/dri:/dev/dri)
    docker_args+=(--volume /dev/dri/by-path:/dev/dri/by-path:ro)
  else
    docker_args+=(--gpus "device=$ids")
  fi
  if [[ $network_mode == "host" ]]; then
    docker_args+=(--network host)
  else
    docker_args+=(--publish "127.0.0.1:$port:$container_port")
  fi
  mapfile -t run_args < <(jq -r '.run_args[]?' <<<"$recipe")
  docker_args+=("${run_args[@]}")
  while IFS= read -r pair; do
    source=$(jq -r '.key' <<<"$pair")
    target=$(jq -r '.value' <<<"$pair")
    source="${source/#\~/$HOME}"
    docker_args+=(--volume "$source:$target")
  done < <(jq -c '(.volumes // {}) | to_entries[]' <<<"$recipe")
  while IFS= read -r pair; do
    docker_args+=(--env "$(jq -r '.key + "=" + (.value | tostring)' <<<"$pair")")
  done < <(jq -c '(.env // {}) | to_entries[]' <<<"$recipe")
  docker_args+=("$image")
  mapfile -t engine_args < <(jq -r '.args[]?' <<<"$recipe")
  docker_args+=("${engine_args[@]}")
  argv_json=$(printf '%s\0' "${docker_args[@]}" | jq -Rs 'split("\u0000")[:-1]')

  jq --argjson argv "$argv_json" --argjson port "$port" --argjson port_available "$port_available" --arg container "$AI_CONTAINER" '. + {plan: {container: $container, port: $port, port_available: $port_available, docker_argv: $argv}}' <<<"$resolution"
}

ai_accept() {
  local port="$1" model="$2" timeout="${OMARCHY_AI_ACCEPT_TIMEOUT:-7200}"
  local deadline models="{}" reply
  deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    models=$(curl --fail --silent --max-time 5 "http://127.0.0.1:$port/v1/models" 2>/dev/null || true)
    if jq -e --arg model "$model" '.data[]?.id == $model' <<<"$models" >/dev/null 2>&1; then
      break
    fi
    if [[ $(docker inspect --format '{{.State.Running}}' "$AI_CONTAINER" 2>/dev/null) != "true" ]]; then
      return 1
    fi
    sleep 5
  done
  jq -e --arg model "$model" '.data[]?.id == $model' <<<"$models" >/dev/null 2>&1 || return 1
  reply=$(curl --fail --silent --max-time 300 "http://127.0.0.1:$port/v1/chat/completions" --header "Content-Type: application/json" --data "$(jq -n --arg model "$model" '{model: $model, messages: [{role: "user", content: "Reply with the single word ready"}], stream: false}')") || return 1
  jq -e '.choices[0].message.content != null or .choices[0].message.tool_calls != null' <<<"$reply" >/dev/null
}

ai_write_state() {
  local plan="$1" tmp
  mkdir -p "$AI_STATE_DIR"
  tmp=$(mktemp "$AI_STATE_DIR/recipe.XXXXXX")
  jq '{schema_version: 1, recipe_id: .recipe.name, name: .recipe.name, label: .recipe.label, served_name: .recipe.served_name, image: .recipe.image, port: .plan.port, container: .plan.container, hardware_id: .hardware.hardware_id, device_ids: .selected_device_ids, context_window: (.recipe.context_window // 8192)}' <<<"$plan" >"$tmp"
  mv "$tmp" "$AI_STATE_FILE"
}

ai_validate_agent_configs() {
  local agent dir file
  for agent in pi omp; do
    dir="$HOME/.$agent/agent"
    for file in models.json settings.json; do
      if [[ -f $dir/$file ]] && ! jq -e 'type == "object"' "$dir/$file" >/dev/null 2>&1; then
        echo "$dir/$file must contain a JSON object before Local AI can configure it." >&2
        return 1
      fi
    done
  done
}

ai_configure_agents() {
  local plan="$1" set_default="${2:-false}"
  local endpoint model label context thinking reasoning vision agent dir provider tmp source
  endpoint="http://127.0.0.1:$(jq -r '.plan.port' <<<"$plan")/v1"
  model=$(jq -r '.recipe.served_name' <<<"$plan")
  label=$(jq -r '.recipe.label' <<<"$plan")
  context=$(jq -r '.recipe.context_window // 8192' <<<"$plan")
  thinking=$(jq -r '.recipe.thinking_format // "openai"' <<<"$plan")
  reasoning=$(jq -r '.recipe.reasoning // false' <<<"$plan")
  vision=$(jq -r '.recipe.vision // false' <<<"$plan")
  provider=$(jq -n --arg url "$endpoint" --arg model "$model" --arg label "$label" --arg thinking "$thinking" --argjson context "$context" --argjson reasoning "$reasoning" --argjson vision "$vision" '{baseUrl: $url, apiKey: "local", api: "openai-completions", models: [{id: $model, name: ($label + " (local)"), reasoning: $reasoning, input: (if $vision then ["text", "image"] else ["text"] end), contextWindow: $context, cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, compat: {supportsDeveloperRole: false, supportsReasoningEffort: false, thinkingFormat: $thinking, supportsStore: false, supportsStrictMode: false, supportsUsageInStreaming: false}}]}')
  for agent in pi omp; do
    dir="$HOME/.$agent/agent"
    mkdir -p "$dir"
    source=$(cat "$dir/models.json" 2>/dev/null || printf '{}')
    [[ -f $dir/models.json.bak.omarchy-local-ai ]] || printf '%s\n' "$source" >"$dir/models.json.bak.omarchy-local-ai"
    tmp=$(mktemp "$dir/models.XXXXXX")
    jq --argjson provider "$provider" '.providers.local = $provider' <<<"$source" >"$tmp"
    mv "$tmp" "$dir/models.json"
    source=$(cat "$dir/settings.json" 2>/dev/null || printf '{}')
    [[ -f $dir/settings.json.bak.omarchy-local-ai ]] || printf '%s\n' "$source" >"$dir/settings.json.bak.omarchy-local-ai"
    tmp=$(mktemp "$dir/settings.XXXXXX")
    jq --arg model "$model" --argjson set_default "$set_default" 'if $set_default or .defaultProvider == null or .defaultProvider == "local" then .defaultProvider = "local" | .defaultModel = $model else . end' <<<"$source" >"$tmp"
    mv "$tmp" "$dir/settings.json"
  done
}

ai_unconfigure_agents() {
  local agent dir source backup previous_provider previous_model tmp
  for agent in pi omp; do
    dir="$HOME/.$agent/agent"
    [[ -d $dir ]] || continue
    if [[ -f $dir/models.json.bak.omarchy-local-ai ]]; then
      source=$(cat "$dir/models.json" 2>/dev/null || printf '{}')
      backup=$(cat "$dir/models.json.bak.omarchy-local-ai")
      previous_provider=$(jq -c '.providers.local // null' <<<"$backup")
      tmp=$(mktemp "$dir/models.XXXXXX")
      jq --argjson previous "$previous_provider" 'if $previous == null then del(.providers.local) else .providers.local = $previous end' <<<"$source" >"$tmp"
      mv "$tmp" "$dir/models.json"
      rm -f "$dir/models.json.bak.omarchy-local-ai"
    elif [[ -f $dir/models.json ]]; then
      source=$(cat "$dir/models.json")
      tmp=$(mktemp "$dir/models.XXXXXX")
      jq 'del(.providers.local)' <<<"$source" >"$tmp"
      mv "$tmp" "$dir/models.json"
    fi
    if [[ -f $dir/settings.json.bak.omarchy-local-ai ]]; then
      source=$(cat "$dir/settings.json" 2>/dev/null || printf '{}')
      backup=$(cat "$dir/settings.json.bak.omarchy-local-ai")
      previous_provider=$(jq -c '.defaultProvider // null' <<<"$backup")
      previous_model=$(jq -c '.defaultModel // null' <<<"$backup")
      tmp=$(mktemp "$dir/settings.XXXXXX")
      jq --argjson provider "$previous_provider" --argjson model "$previous_model" 'if .defaultProvider == "local" then (if $provider == null then del(.defaultProvider) else .defaultProvider = $provider end) | (if $model == null then del(.defaultModel) else .defaultModel = $model end) else . end' <<<"$source" >"$tmp"
      mv "$tmp" "$dir/settings.json"
      rm -f "$dir/settings.json.bak.omarchy-local-ai"
    elif [[ -f $dir/settings.json ]]; then
      source=$(cat "$dir/settings.json")
      tmp=$(mktemp "$dir/settings.XXXXXX")
      jq 'if .defaultProvider == "local" then del(.defaultProvider, .defaultModel) else . end' <<<"$source" >"$tmp"
      mv "$tmp" "$dir/settings.json"
    fi
  done
}

ai_status_json() {
  if [[ ! -f $AI_STATE_FILE ]]; then
    jq -n '{state: "not-setup", ready: false}'
    return
  fi
  local running=false ready=false port recipe model
  port=$(jq -r '.port' "$AI_STATE_FILE")
  recipe=$(jq -r '.recipe_id // .name' "$AI_STATE_FILE")
  model=$(jq -r '.served_name' "$AI_STATE_FILE")
  if [[ $(docker inspect --format '{{.State.Running}}' "$AI_CONTAINER" 2>/dev/null) == "true" ]]; then
    running=true
    if curl --fail --silent --max-time 3 "http://127.0.0.1:$port/v1/models" | jq -e --arg model "$model" '.data[]?.id == $model' >/dev/null 2>&1; then
      ready=true
    fi
  fi
  jq -n --arg recipe "$recipe" --arg model "$model" --argjson port "$port" --argjson running "$running" --argjson ready "$ready" '{state: (if $ready then "ready" elif $running then "loading" else "stopped" end), ready: $ready, running: $running, recipe_id: $recipe, model: $model, port: $port, endpoint: ("http://127.0.0.1:" + ($port | tostring) + "/v1")}'
}

ai_doctor_json() {
  local hardware resolution status checks capacity_ok capacity_detail port port_ok managed_running
  hardware=$(ai_hardware_json)
  resolution=$(ai_resolve_json)
  status=$(ai_status_json)
  managed_running=$(jq -r '.running // false' <<<"$status")
  capacity_ok=$(jq -r '.availability.available // false' <<<"$resolution")
  capacity_detail=$(jq -r '.availability.reason // .error.message' <<<"$resolution")
  port=$(jq -r '.port' "$(ai_catalog_path)")
  port_ok=false
  if ai_port_available "$port"; then
    port_ok=true
  fi
  if $managed_running; then
    capacity_ok=true
    capacity_detail="managed service is using the selected GPUs"
    port_ok=true
  fi
  checks=$(jq --argjson capacity_ok "$capacity_ok" --arg capacity_detail "$capacity_detail" --argjson port_ok "$port_ok" --arg port "$port" --argjson managed "$managed_running" '[{id: "gpu", ok: (.devices | length > 0), detail: (.hardware_id)}, {id: "docker", ok: .runtime.ready, detail: (if .runtime.ready then .runtime.version else "install Docker, then enable and start docker.service" end)}, {id: "nvidia-runtime", ok: .runtime.nvidia, detail: (if .runtime.nvidia then "ready" else "install nvidia-container-toolkit, then restart Docker" end)}, {id: "disk", ok: (.disk_free_bytes >= 21474836480), detail: ((.disk_free_bytes / 1073741824 | floor | tostring) + " GB free")}, {id: "port", ok: $port_ok, detail: (if $managed then ($port + " used by the managed service") elif $port_ok then ($port + " available") else ($port + " already in use") end)}, {id: "capacity", ok: $capacity_ok, detail: $capacity_detail}]' <<<"$hardware")
  jq -n --argjson hardware "$hardware" --argjson checks "$checks" '{ok: ($checks | all(.ok)), hardware: $hardware, checks: $checks}'
}
