if [[ $# -lt 2 ]]; then
  echo "Must specify selection file and kind of thing!"
  exit
fi

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
export -f get_package_info

filter_user_selected_aur() {
  for package in "$@"; do
    is_aur_package "$package" && echo "$package" >> "$OMARCHY_INSTALL/user-selected-aur.packages" || echo "$package" >> "$OMARCHY_INSTALL/user-selected.packages"
  done
}

fzf_args=(
  --multi
  --header="Select which $2 packages to install."
  --preview 'get_package_info {1}' 
  --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select, escape: none of them'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --color 'pointer:green,marker:green'
)

pkg_names=$(grep -v '^#' "$OMARCHY_INSTALL/$1" | grep -v '^$' | fzf "${fzf_args[@]}")
filter_user_selected_aur $pkg_names
