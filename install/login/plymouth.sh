OMARCHY_DESCRIPTION="Plymouth Boot Splash Theme"

omarchy_install() {
  if [ "$(plymouth-set-default-theme)" != "omarchy" ]; then
    sudo cp -r "$HOME/.local/share/omarchy/default/plymouth" /usr/share/plymouth/themes/omarchy/
    sudo plymouth-set-default-theme omarchy
  fi
}

omarchy_verify() {
  [[ "$(plymouth-set-default-theme)" == "omarchy" ]] || add_error "Plymouth theme not set to omarchy"
  [[ -d /usr/share/plymouth/themes/omarchy ]] || add_error "Omarchy Plymouth theme not installed"
}
