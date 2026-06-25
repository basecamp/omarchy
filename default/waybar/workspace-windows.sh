#!/bin/bash
# Waybar custom module: workspaces with a per-workspace window count badge.
# Renders each workspace number followed by a superscript count of its windows,
# highlights the active workspace, and updates instantly via the Hyprland IPC socket.

# Minimum number of (persistent) workspaces always shown.
MIN_WS=5

# Superscript digits 0-9 for the count badge.
SUP=("⁰" "¹" "²" "³" "⁴" "⁵" "⁶" "⁷" "⁸" "⁹")

to_super() {
  local n="$1" out="" i
  for ((i = 0; i < ${#n}; i++)); do
    out+="${SUP[${n:$i:1}]}"
  done
  printf '%s' "$out"
}

render() {
  local active counts max=$MIN_WS ws c label out=""
  active=$(hyprctl activeworkspace -j | jq -r '.id')

  # Map "id -> window count" for normal (id >= 1) workspaces.
  declare -A counts=()
  while read -r id win; do
    [[ "$id" =~ ^[0-9]+$ ]] && (( id >= 1 )) && counts[$id]=$win
  done < <(hyprctl workspaces -j | jq -r '.[] | "\(.id) \(.windows)"')

  # Show up to the highest populated/active workspace, but at least MIN_WS.
  for id in "${!counts[@]}"; do (( id > max )) && max=$id; done
  [[ "$active" =~ ^[0-9]+$ ]] && (( active > max )) && max=$active

  for ((ws = 1; ws <= max; ws++)); do
    c=${counts[$ws]:-0}
    label="$ws"
    (( c > 0 )) && label+="$(to_super "$c")"
    if [[ "$ws" == "$active" ]]; then
      out+="<span color='#ff3b30'><b>$label</b></span> "
    else
      out+="$label "
    fi
  done

  printf '%s\n' "$out"
}

# Initial paint.
render

# Stream Hyprland events and repaint on anything that changes counts/active ws.
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$SOCKET" 2>/dev/null | while read -r line; do
  case "$line" in
    workspace\>*|createworkspace\>*|destroyworkspace\>*|moveworkspace\>*|\
openwindow\>*|closewindow\>*|movewindow\>*|focusedmon\>*|activespecial\>*)
      render
      ;;
  esac
done
