start_install_log() {
  mkdir -p "$(dirname "$OMARCHY_INSTALL_LOG_FILE")"
  touch "$OMARCHY_INSTALL_LOG_FILE"
  chmod 666 "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true

  export OMARCHY_START_TIME="${OMARCHY_START_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"
  export OMARCHY_START_EPOCH="${OMARCHY_START_EPOCH:-$(date +%s)}"

  echo "=== Omarchy Setup Started: $OMARCHY_START_TIME ===" >>"$OMARCHY_INSTALL_LOG_FILE"
}

stop_install_log() {
  [[ -n ${OMARCHY_INSTALL_LOG_FILE:-} ]] || return 0

  local end_time end_epoch duration mins secs
  end_time=$(date '+%Y-%m-%d %H:%M:%S')
  end_epoch=$(date +%s)

  echo "=== Omarchy Setup Completed: $end_time ===" >>"$OMARCHY_INSTALL_LOG_FILE"

  if [[ -n ${OMARCHY_START_EPOCH:-} ]]; then
    duration=$((end_epoch - OMARCHY_START_EPOCH))
    mins=$((duration / 60))
    secs=$((duration % 60))
    echo "Omarchy setup: ${mins}m ${secs}s" >>"$OMARCHY_INSTALL_LOG_FILE"
  fi
}

run_logged() {
  local script="$1"

  if [[ -z ${OMARCHY_INSTALL_LOG_FILE:-} ]]; then
    bash -eE -c 'source "$1"' bash "$script"
    return
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script" >>"$OMARCHY_INSTALL_LOG_FILE"

  if [[ ${OMARCHY_INSTALL_DEBUG:-} == "1" ]]; then
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' \
      bash -x -eE -c 'source "$1"' bash "$script" </dev/null >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1
  else
    bash -eE -c 'source "$1"' bash "$script" </dev/null >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1
  fi

  local exit_code=$?
  if (( exit_code == 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script" >>"$OMARCHY_INSTALL_LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)" >>"$OMARCHY_INSTALL_LOG_FILE"
  fi

  return $exit_code
}
