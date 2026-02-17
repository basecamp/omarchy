#!/bin/bash

# Show a fuzzy-finder TUI for picking new AUR packages to install.

fzf_args=(
  --multi
  --preview 'yay -Siia {1}'
  --preview-label='alt-p: toggle description, alt-b/B: toggle PKGBUILD, alt-j/k: scroll, tab: multi-select'
  --preview-label-pos='bottom'
  --preview-window 'down:65%:wrap'
  --bind 'alt-p:toggle-preview'
  --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
  --bind 'alt-k:preview-up,alt-j:preview-down'
  --bind 'alt-b:change-preview:yay -Gpa {1} | tail -n +5'
  --bind 'alt-B:change-preview:yay -Siia {1}'
  --color 'pointer:green,marker:green'
)

pkg_names=$(yay -Slqa | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  # Convert newline-separated selections to space-separated for yay
  echo "$pkg_names" | tr '\n' ' ' | xargs yay -S --noconfirm
  sudo updatedb
  omarchy-show-done
fi
