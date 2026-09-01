omarchy_log_to_stdout() {
  [[ ${OMARCHY_LOG_TO_STDOUT:-} == "1" || -z ${OMARCHY_INSTALL_LOG_FILE:-} ]]
}

omarchy_log_line() {
  if omarchy_log_to_stdout; then
    echo "$1"
  else
    echo "$1" >>"$OMARCHY_INSTALL_LOG_FILE"
  fi
}

start_install_log() {
  if ! omarchy_log_to_stdout; then
    mkdir -p "$(dirname "$OMARCHY_INSTALL_LOG_FILE")"

    # Only root writes here through this helper: the ISO runs the target setup
    # with OMARCHY_LOG_TO_STDOUT=1 and copies the log itself, so this branch is
    # reached when omarchy-apply-system or omarchy-apply-hardware is rerun by
    # hand on an installed system. The old world-writable mode then let every
    # local account read the step output and append forged lines.
    #
    # The log is published as a fresh file, not chmodded in place. A chmod only
    # changes who can open the file from now on; a process that already had the
    # old 0666 file open keeps writing to it. Building the new file privately
    # and moving it over the old name leaves such a descriptor pointing at an
    # unlinked inode. Existing content is carried across.
    #
    # Mode 0640 with group wheel: the owner account is in wheel and already has
    # full sudo, so wheel read gives up nothing, and omarchy-upload-log can
    # still read the log as that user. Other local accounts are shut out.
    local old_umask staged
    old_umask=$(umask)
    umask 077
    staged=$(mktemp "$OMARCHY_INSTALL_LOG_FILE.XXXXXX")
    umask "$old_umask"
    if [[ -f $OMARCHY_INSTALL_LOG_FILE ]]; then
      cat "$OMARCHY_INSTALL_LOG_FILE" >>"$staged" 2>/dev/null || true
    fi
    chgrp wheel "$staged" 2>/dev/null || true
    chmod 640 "$staged"
    mv -f "$staged" "$OMARCHY_INSTALL_LOG_FILE"
  fi

  export OMARCHY_START_TIME="${OMARCHY_START_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"
  export OMARCHY_START_EPOCH="${OMARCHY_START_EPOCH:-$(date +%s)}"

  omarchy_log_line "=== Omarchy Setup Started: $OMARCHY_START_TIME ==="
}

stop_install_log() {
  local end_time end_epoch duration mins secs
  end_time=$(date '+%Y-%m-%d %H:%M:%S')
  end_epoch=$(date +%s)

  omarchy_log_line "=== Omarchy Setup Completed: $end_time ==="

  if [[ -n ${OMARCHY_START_EPOCH:-} ]]; then
    duration=$((end_epoch - OMARCHY_START_EPOCH))
    mins=$((duration / 60))
    secs=$((duration % 60))
    omarchy_log_line "Omarchy setup: ${mins}m ${secs}s"
  fi
}

run_logged() {
  local script="$1"
  local exit_code errexit_was_set=0

  omarchy_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script"

  case $- in
    *e*)
      errexit_was_set=1
      set +e
      ;;
  esac

  local runner=(bash -eE)
  if [[ ${OMARCHY_INSTALL_DEBUG:-} == "1" ]]; then
    runner=(bash -x -eE)
  fi

  if omarchy_log_to_stdout; then
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' \
      "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null 2>&1
  else
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' \
      "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1
  fi

  exit_code=$?
  (( errexit_was_set )) && set -e

  if (( exit_code == 0 )); then
    omarchy_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script"
  else
    omarchy_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)"
  fi

  return $exit_code
}
