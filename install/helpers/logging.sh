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

omarchy_install_log_parent_is_safe() {
  local parent="$1" canonical current owner mode uid first=1
  uid=$(/usr/bin/id -u) || return 1

  [[ $parent == /* && -d $parent && ! -L $parent ]] || return 1
  canonical=$(/usr/bin/realpath -e -- "$parent" 2>/dev/null) || return 1
  [[ $canonical == "$parent" ]] || return 1

  # Every ancestor owner could make their directory writable and replace the
  # descendant path. Trust only root/current-owned ancestors, and allow the
  # exact root-owned sticky /tmp as the boundary for private test overrides.
  current=$parent
  while :; do
    [[ -d $current && ! -L $current ]] || return 1
    owner=$(/usr/bin/stat -c '%u' -- "$current" 2>/dev/null) || return 1
    mode=$(/usr/bin/stat -c '%a' -- "$current" 2>/dev/null) || return 1
    [[ $owner =~ ^[0-9]+$ && $mode =~ ^[0-7]+$ ]] || return 1

    [[ $owner == 0 || $owner == "$uid" ]] || return 1
    if ((first)); then
      [[ $owner == "$uid" ]] && ! ((8#$mode & 0022)) || return 1
      first=0
    elif [[ $current == /tmp ]]; then
      [[ $owner == 0 && $mode == 1777 ]] || return 1
    elif ((8#$mode & 0022)); then
      return 1
    fi

    [[ $current == / ]] && break
    current=$(/usr/bin/dirname -- "$current") || return 1
  done
}

omarchy_detach_failed_install_log() {
  local path=$1

  if ! /usr/bin/rm -f -- "$path" || [[ -e $path || -L $path ]]; then
    echo "URGENT: could not detach the unsafe Omarchy install-log inode: $path" >&2
    return 1
  fi
}

prepare_install_log_file() {
  local path=${OMARCHY_INSTALL_LOG_FILE:-} parent basename canonical uid owner mode temp=""
  uid=$(/usr/bin/id -u) || return 1

  if [[ -z $path || $path != /* || $path == *$'\n'* || $path == *$'\r'* ]]; then
    echo "The Omarchy install log path must be a clean absolute path." >&2
    return 1
  fi
  canonical=$(/usr/bin/realpath -m -- "$path" 2>/dev/null) || return 1
  if [[ $canonical != "$path" ]]; then
    echo "Refusing a non-canonical Omarchy install log path: $path" >&2
    return 1
  fi

  parent=$(/usr/bin/dirname -- "$path") || return 1
  basename=${path##*/}
  if [[ -z $basename ]] || ! omarchy_install_log_parent_is_safe "$parent"; then
    echo "Refusing an Omarchy install log beneath an unsafe parent: $parent" >&2
    return 1
  fi

  if [[ -e $path || -L $path ]]; then
    if [[ -L $path || ! -f $path ]]; then
      echo "Refusing to replace a symlink or non-regular Omarchy install log: $path" >&2
      return 1
    fi
    owner=$(/usr/bin/stat -c '%u' -- "$path" 2>/dev/null) || return 1
    if [[ $owner != "$uid" ]]; then
      echo "Refusing to replace an Omarchy install log owned by another account: $path" >&2
      return 1
    fi
    # Stop new foreign opens immediately. A successful transaction below also
    # replaces the inode so already-open foreign descriptors become detached.
    if ! /usr/bin/chmod 0600 -- "$path" ||
      [[ $(/usr/bin/stat -c '%a' -- "$path" 2>/dev/null) != 600 ]]; then
      omarchy_detach_failed_install_log "$path" || true
      echo "Could not tighten the existing Omarchy install log." >&2
      return 1
    fi
  fi

  # Always publish a fresh inode. Merely chmodding a formerly world-writable
  # file would leave an unrelated user's already-open descriptor writable.
  if ! temp=$(/usr/bin/mktemp -- "$parent/.${basename}.private.XXXXXXXX"); then
    omarchy_detach_failed_install_log "$path" || true
    echo "Could not allocate a fresh private Omarchy install log." >&2
    return 1
  fi
  if ! /usr/bin/chmod 0600 -- "$temp" ||
    [[ -L $temp || ! -f $temp ]] ||
    [[ $(/usr/bin/stat -c '%u' -- "$temp" 2>/dev/null) != "$uid" ]]; then
    /usr/bin/rm -f -- "$temp"
    omarchy_detach_failed_install_log "$path" || true
    echo "Could not create a private Omarchy install log." >&2
    return 1
  fi

  if [[ -e $path ]] && ! /usr/bin/cat -- "$path" >"$temp"; then
    /usr/bin/rm -f -- "$temp"
    omarchy_detach_failed_install_log "$path" || true
    echo "Could not preserve the existing Omarchy install log." >&2
    return 1
  fi
  if ! /usr/bin/mv -fT -- "$temp" "$path"; then
    /usr/bin/rm -f -- "$temp"
    omarchy_detach_failed_install_log "$path" || true
    echo "Could not atomically publish the private Omarchy install log." >&2
    return 1
  fi

  if ! owner=$(/usr/bin/stat -c '%u' -- "$path" 2>/dev/null) ||
    ! mode=$(/usr/bin/stat -c '%a' -- "$path" 2>/dev/null); then
    omarchy_detach_failed_install_log "$path" || true
    echo "Could not verify the published Omarchy install log." >&2
    return 1
  fi
  if [[ -L $path || ! -f $path || $owner != "$uid" || $mode != 600 ]]; then
    omarchy_detach_failed_install_log "$path" || true
    echo "The published Omarchy install log failed its ownership or mode check." >&2
    return 1
  fi
}

start_install_log() {
  if ! omarchy_log_to_stdout; then
    prepare_install_log_file || return 1
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
