as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}
