start_log_output() {
  local ANSI_SAVE_CURSOR="\033[s"
  local ANSI_RESTORE_CURSOR="\033[u"
  local ANSI_CLEAR_LINE="\033[2K"
  local ANSI_HIDE_CURSOR="\033[?25l"
  local ANSI_RESET="\033[0m"
  local ANSI_GRAY="\033[90m"

  # Save cursor position and hide cursor
  printf $ANSI_SAVE_CURSOR
  printf $ANSI_HIDE_CURSOR

  (
    # Disable all traps in background monitor to prevent duplicate error handling
    # when this process is killed during error cleanup
    trap - ERR INT TERM EXIT

    local log_lines=20
    local max_line_width=$((LOGO_WIDTH - 4))

    while true; do
      # Read the last N lines into an array
      mapfile -t current_lines < <(tail -n $log_lines "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null)

      # Build complete output buffer with escape sequences
      output=""
      for ((i = 0; i < log_lines; i++)); do
        line="${current_lines[i]:-}"

        # Truncate if needed
        if (( ${#line} > max_line_width )); then
          line="${line:0:$max_line_width}..."
        fi

        # Add clear line escape and formatted output for each line
        # Use simple ASCII arrow on ARM/Asahi/VMs, Unicode elsewhere
        local arrow="→"
        if [[ -n $OMARCHY_ARM ]] || [[ $ASAHI_ALARM == "true" ]] || [[ -n $OMARCHY_VIRTUALIZATION ]]; then
          arrow="->"
        fi

        if [[ -n $line ]]; then
          output+="${ANSI_CLEAR_LINE}${ANSI_GRAY}${PADDING_LEFT_SPACES}  ${arrow} ${line}${ANSI_RESET}\n"
        else
          output+="${ANSI_CLEAR_LINE}${PADDING_LEFT_SPACES}\n"
        fi
      done

      printf "${ANSI_RESTORE_CURSOR}%b" "$output"

      # Use bash built-in read with timeout instead of external sleep command
      # This prevents "command not found" errors when coreutils is being upgraded
      read -t 0.1 -N 1 2>/dev/null || true
    done
  ) &
  monitor_pid=$!
}

stop_log_output() {
  if [[ -n ${monitor_pid:-} ]]; then
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    unset monitor_pid
  fi
}

start_install_log() {
  sudo touch "$OMARCHY_INSTALL_LOG_FILE"
  sudo chmod 666 "$OMARCHY_INSTALL_LOG_FILE"

  # Create symlink for easy access (scripts can use /var/log/omarchy-install.log)
  sudo ln -sf "$OMARCHY_INSTALL_LOG_FILE" "/var/log/omarchy-install.log" 2>/dev/null || true

  # Clean up old logs (keep last 10)
  sudo find /var/log -name "omarchy-install-*.log" -type f 2>/dev/null | sort -r | tail -n +11 | xargs -r sudo rm -f 2>/dev/null || true

  export OMARCHY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

  echo "=== Omarchy Installation Started: $OMARCHY_START_TIME ===" >>"$OMARCHY_INSTALL_LOG_FILE"
  start_log_output
}

stop_install_log() {
  stop_log_output
  show_cursor

  if [[ -n ${OMARCHY_INSTALL_LOG_FILE:-} ]]; then
    OMARCHY_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== Omarchy Installation Completed: $OMARCHY_END_TIME ===" >>"$OMARCHY_INSTALL_LOG_FILE"
    echo "" >>"$OMARCHY_INSTALL_LOG_FILE"
    echo "=== Installation Time Summary ===" >>"$OMARCHY_INSTALL_LOG_FILE"

    if [[ -f "/var/log/archinstall/install.log" ]]; then
      ARCHINSTALL_START=$(grep -m1 '^\[' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
      ARCHINSTALL_END=$(grep 'Installation completed without any errors' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)

      if [[ -n $ARCHINSTALL_START ]] && [[ -n $ARCHINSTALL_END ]]; then
        ARCH_START_EPOCH=$(date -d "$ARCHINSTALL_START" +%s)
        ARCH_END_EPOCH=$(date -d "$ARCHINSTALL_END" +%s)
        ARCH_DURATION=$((ARCH_END_EPOCH - ARCH_START_EPOCH))

        ARCH_MINS=$((ARCH_DURATION / 60))
        ARCH_SECS=$((ARCH_DURATION % 60))

        echo "Archinstall: ${ARCH_MINS}m ${ARCH_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"
      fi
    fi

    if [[ -n $OMARCHY_START_TIME ]]; then
      OMARCHY_START_EPOCH=$(date -d "$OMARCHY_START_TIME" +%s)
      OMARCHY_END_EPOCH=$(date -d "$OMARCHY_END_TIME" +%s)
      OMARCHY_DURATION=$((OMARCHY_END_EPOCH - OMARCHY_START_EPOCH))

      OMARCHY_MINS=$((OMARCHY_DURATION / 60))
      OMARCHY_SECS=$((OMARCHY_DURATION % 60))

      echo "Omarchy:     ${OMARCHY_MINS}m ${OMARCHY_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"

      if [[ -n $ARCH_DURATION ]]; then
        TOTAL_DURATION=$((ARCH_DURATION + OMARCHY_DURATION))
        TOTAL_MINS=$((TOTAL_DURATION / 60))
        TOTAL_SECS=$((TOTAL_DURATION % 60))
        echo "Total:       ${TOTAL_MINS}m ${TOTAL_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"
      fi
    fi
    echo "=================================" >>"$OMARCHY_INSTALL_LOG_FILE"

    echo "Rebooting system..." >>"$OMARCHY_INSTALL_LOG_FILE"
  fi
}

run_logged() {
  local script="$1"

  export CURRENT_SCRIPT="$script"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script" >>"$OMARCHY_INSTALL_LOG_FILE"

  # Use bash -c to create a clean subshell, preserving critical environment variables
  bash -c "
    # Disable error trap in subshell to prevent duplicate error display
    # Parent shell will handle error display, subshell just logs and exits
    trap - ERR INT TERM EXIT

    export OMARCHY_ARM='$OMARCHY_ARM'
    export ASAHI_ALARM='$ASAHI_ALARM'
    export OMARCHY_INSTALL='$OMARCHY_INSTALL'
    export OMARCHY_PATH='$OMARCHY_PATH'
    export OMARCHY_CHROOT_INSTALL='$OMARCHY_CHROOT_INSTALL'
    export OMARCHY_ONLINE_INSTALL='$OMARCHY_ONLINE_INSTALL'
    export OMARCHY_VIRTUALIZATION='$OMARCHY_VIRTUALIZATION'
    export OMARCHY_VMWARE='$OMARCHY_VMWARE'
    export OMARCHY_SKIP_LIMINE='$OMARCHY_SKIP_LIMINE'
    export OMARCHY_VM_SOFTWARE_RENDERING='$OMARCHY_VM_SOFTWARE_RENDERING'
    export SKIP_ALL='${SKIP_ALL:-}'
    export SKIP_YARU='$SKIP_YARU'
    export SKIP_OBS='$SKIP_OBS'
    export SKIP_PINTA='$SKIP_PINTA'
    export SKIP_GHOSTTY='${SKIP_GHOSTTY:-}'
    export SKIP_SIGNAL_DESKTOP_BETA='$SKIP_SIGNAL_DESKTOP_BETA'
    export OMARCHY_REPO='$OMARCHY_REPO'
    export OMARCHY_REF='$OMARCHY_REF'
    export OMARCHY_USER_NAME='$OMARCHY_USER_NAME'
    export OMARCHY_USER_EMAIL='$OMARCHY_USER_EMAIL'
    export PATH='$PATH'
    source '$script'
  " >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1

  local exit_code=$?

  if (( exit_code == 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script" >>"$OMARCHY_INSTALL_LOG_FILE"
    unset CURRENT_SCRIPT
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)" >>"$OMARCHY_INSTALL_LOG_FILE"
  fi

  return $exit_code
}
