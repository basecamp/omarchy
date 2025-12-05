is_aur_package() {
  local package_name=$1
  
  # Check if in official
  pacman -Qi "$package_name" &> /dev/null && return 0
  yay -Q --aur "$package_name" &> /dev/null && return 1
  echo "Unknown package in neither official nor AUR!: $package_name"
}

get_package_info() {
  local package_name=$1
  if is_aur_package "$package_name"; then
    yay -Siia "$package_name"
  else
    pacman -Sii "$package_name"
  fi
}
