pause_log() {
  stop_log_output
}

unpause_log() {
  text=$1
  clear_logo
  gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "${text:-Installing...}" #"Installing..."
  echo
  start_log_output
}
