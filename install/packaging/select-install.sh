if [[ $# -lt 2 ]]; then
  echo "Must specify selection file and kind of thing!"
  exit
fi

fzf_args=(
  --multi
  --header="Select which $2 packages to install."
  --preview 'pacman -Sii {1}' #'echo Preview for {1}!' 
  --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --color 'pointer:green,marker:green'
)

pkg_names=$(grep -v '^#' "$OMARCHY_INSTALL/$1" | grep -v '^$' | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then # If nonempty selection.
  # Convert newline-separated selections to space-separated for yay
  echo "$pkg_names" | tr '\n' ' ' | xargs sudo pacman -S --noconfirm --needed
#  echo 'Selected following from file:'
#  echo "$pkg_names"
#else
#  echo 'No package selected! :'"'"'('
fi
