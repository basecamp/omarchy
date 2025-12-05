if [[ $# -lt 2 ]]; then
  echo "Must specify selection file and kind of thing!"
  exit
fi

filter_user_selected_aur() {
  for package in "$@"; do
    is_aur_package "$package" && echo "$package" >> "user-selected-aur.packages" || echo "$package" >> "user-selected.packages"
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

pkg_names=$(grep -v '^#' "$1" | grep -v '^$' | fzf "${fzf_args[@]}")
filter_user_selected_aur $pkg_names
