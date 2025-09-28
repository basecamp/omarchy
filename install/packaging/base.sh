OMARCHY_DESCRIPTION="Base Packages"

omarchy_install() {
  # Install all base packages
  mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$')
  sudo pacman -S --noconfirm --needed "${packages[@]}"
}

omarchy_verify() {
  [[ -f "$OMARCHY_INSTALL/omarchy-base.packages" ]] || add_error "Base packages list missing"

  # Check if all base packages are installed
  if [[ -f "$OMARCHY_INSTALL/omarchy-base.packages" ]]; then
    mapfile -t packages < <(grep -v '^#' "$OMARCHY_INSTALL/omarchy-base.packages" | grep -v '^$')

    local missing_packages=()
    for package in "${packages[@]}"; do
      if ! pacman -Q "$package" &>/dev/null; then
        missing_packages+=("$package")
      fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
      add_error "Missing base packages: ${missing_packages[*]}"
    fi
  fi
}
