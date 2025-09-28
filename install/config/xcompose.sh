OMARCHY_DESCRIPTION="XCompose"

omarchy_install() {
  # Set default XCompose that is triggered with CapsLock
  tee ~/.XCompose >/dev/null <<EOF
include "%H/.local/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
}

omarchy_verify() {
  [[ -f ~/.XCompose ]] || add_error "XCompose file missing"

  if [[ -f ~/.XCompose ]]; then
    grep -q "include.*xcompose" ~/.XCompose || add_error "XCompose include directive missing"
  fi
}
