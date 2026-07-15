# Rsync-on-change watchers: rsw starts one in the background, lsw lists, dsw stops
rsw() {
  (( $# != 2 )) && echo "Usage: rsw <source> <destination>" && return 1
  local src="${1%/}" dest="$2"
  # Reuse one SSH connection per login, so 1Password only prompts once.
  local sockets="${XDG_RUNTIME_DIR:-$HOME/.ssh/sockets}"
  mkdir -p "$sockets"
  local rsh="ssh -o ControlMaster=auto -o ControlPath=$sockets/rsw-%r@%h:%p -o ControlPersist=yes"
  setsid --fork env RSYNC_RSH="$rsh" bash -c 'rsync -a "$1/" "$2"; while inotifywait -r -q -e modify,create,delete,move "$1"; do rsync -a "$1/" "$2"; done' rsw-watch "$src" "$dest" >/dev/null 2>&1
  echo "Watching $src -> $dest"
}

lsw() {
  local pid cmd rest found=0
  while read -r pid cmd; do
    rest="${cmd##*rsw-watch }"
    echo "$pid: ${rest% *} -> ${rest##* }"
    found=1
  done < <(pgrep -af 'rsw-watch ')
  (( found )) || echo "No active watches"
}

dsw() {
  local pid found=0
  for pid in $(pgrep -f 'rsw-watch '); do
    kill -- -"$pid" 2>/dev/null && echo "Stopped watch (pid $pid)" && found=1
  done
  (( found )) || echo "No active watches"
}
