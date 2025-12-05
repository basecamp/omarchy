if [[ $# -lt 2 ]]; then
  echo "Must specify selection file and kind of thing!"
  exit 1
fi

is_aur_package() {
  local package_name=$1
  # Check if in aur list
  if grep -q "^$package_name\$" "$OMARCHY_INSTALL/omarch-me-aur.packages"; then
    return 0
  else
    return 1
  fi
}
# Have to export functions for fzf
export -f is_aur_package

get_package_info() {
  local package_name=$1
  if is_aur_package "$package_name"; then
    yay -Siia "$package_name" || echo "Failed to get info for $package_name"
  else
    pacman -Sii "$package_name" || echo "Failed to get info for $package_name"
  fi
}
# Have to export functions for fzf
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

pkg_names=$(grep -v '^#' "$OMARCHY_INSTALL/$1" | grep -v '^$' | fzf "${fzf_args[@]}" || true)
filter_user_selected_aur $pkg_names
