# Log output UI for .automated_script.sh
# Tails one or more log files and displays them with pretty formatting
# Supports multiple files: start_log_output file1 file2 file3
# Uses tail -F so it waits for files that don't exist yet
start_log_output() {
  local ANSI_SAVE_CURSOR="\033[s"
  local ANSI_RESTORE_CURSOR="\033[u"
  local ANSI_CLEAR_LINE="\033[2K"
  local ANSI_HIDE_CURSOR="\033[?25l"
  local ANSI_RESET="\033[0m"
  local ANSI_GRAY="\033[90m"
  
  # Support multiple log files, default to main install log
  local log_files=("${@:-/var/log/omarchy-install.log}")

  # Save cursor position and hide cursor
  printf $ANSI_SAVE_CURSOR
  printf $ANSI_HIDE_CURSOR

  (
    local log_lines=20
    local max_line_width=$((LOGO_WIDTH - 4))
    
    # Use tail -F to follow multiple files, even if they don't exist yet
    # -F = --follow=name --retry (follows by name, waits for files to appear)
    # -n 0 = start from end (don't show existing content)
    # -q = quiet (no headers when switching between files)
    tail -F -n 0 -q "${log_files[@]}" 2>/dev/null | while IFS= read -r line; do
      # Keep a rolling buffer of the last N lines
      if [ ! -f /tmp/omarchy-log-buffer.txt ]; then
        touch /tmp/omarchy-log-buffer.txt
      fi
      
      # Append new line and keep only last N lines
      echo "$line" >> /tmp/omarchy-log-buffer.txt
      tail -n $log_lines /tmp/omarchy-log-buffer.txt > /tmp/omarchy-log-buffer.tmp
      mv /tmp/omarchy-log-buffer.tmp /tmp/omarchy-log-buffer.txt
      
      # Read current buffer
      mapfile -t current_lines < /tmp/omarchy-log-buffer.txt

      # Build complete output buffer with escape sequences
      output=""
      for ((i = 0; i < log_lines; i++)); do
        current_line="${current_lines[i]:-}"

        # Truncate if needed
        if [ ${#current_line} -gt $max_line_width ]; then
          current_line="${current_line:0:$max_line_width}..."
        fi

        # Add clear line escape and formatted output for each line
        if [ -n "$current_line" ]; then
          output+="${ANSI_CLEAR_LINE}${ANSI_GRAY}${PADDING_LEFT_SPACES}  → ${current_line}${ANSI_RESET}\n"
        else
          output+="${ANSI_CLEAR_LINE}${PADDING_LEFT_SPACES}\n"
        fi
      done

      printf "${ANSI_RESTORE_CURSOR}%b" "$output"
    done
  ) &
  monitor_pid=$!
}

stop_log_output() {
  local ANSI_SHOW_CURSOR="\033[?25h"
  
  if [ -n "${monitor_pid:-}" ]; then
    # Disown the process to prevent "Killed" message
    disown $monitor_pid 2>/dev/null || true
    
    # Kill child processes first (tail -F) with SIGKILL
    pkill -9 -P $monitor_pid 2>/dev/null || true
    
    # Kill the monitor process with SIGKILL for immediate termination
    kill -9 $monitor_pid 2>/dev/null || true
    
    # Clean up temp buffer file
    rm -f /tmp/omarchy-log-buffer.txt /tmp/omarchy-log-buffer.tmp 2>/dev/null || true
    
    unset monitor_pid
  fi
  
  # Restore cursor visibility
  printf $ANSI_SHOW_CURSOR
}
