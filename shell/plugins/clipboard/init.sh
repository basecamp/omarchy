#!/bin/bash

current_script=${1:-}
[[ -n $current_script ]] || exit 0

is_clipboard_capture() {
  local path=$1

  [[ $path == */shell/plugins/clipboard/capture.sh ]]
}

watched_script_for_pid() {
  local pid=$1
  local -a args=()
  local i

  [[ -r /proc/$pid/cmdline ]] || return 1
  mapfile -d '' -t args <"/proc/$pid/cmdline" || return 1
  ((${#args[@]} > 0)) || return 1

  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ ${args[i]} == "--watch" ]]; then
      printf '%s\n' "${args[i + 1]:-}"
      return 0
    fi
  done

  return 1
}

for pid in $(pgrep -x wl-paste 2>/dev/null || true); do
  watched_script=$(watched_script_for_pid "$pid" || true)
  [[ -n $watched_script ]] || continue
  is_clipboard_capture "$watched_script" || continue

  if [[ $watched_script == $current_script || ! -e $watched_script ]]; then
    kill "$pid" 2>/dev/null || true
  fi
done
