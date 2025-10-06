OMARCHY_DESCRIPTION="Git"

omarchy_install() {
  # Ensure git settings live under ~/.config
  mkdir -p ~/.config/git
  touch ~/.config/git/config

  # Set common git aliases
  git config --global alias.co checkout
  git config --global alias.br branch
  git config --global alias.ci commit
  git config --global alias.st status
  git config --global pull.rebase true
  git config --global init.defaultBranch master

  # Set identification from install inputs
  if [[ -n "${OMARCHY_USER_NAME//[[:space:]]/}" ]]; then
    git config --global user.name "$OMARCHY_USER_NAME"
  fi

  if [[ -n "${OMARCHY_USER_EMAIL//[[:space:]]/}" ]]; then
    git config --global user.email "$OMARCHY_USER_EMAIL"
  fi
}

omarchy_verify() {
  [[ -d ~/.config/git ]] || add_error "Git config directory missing"
  [[ -f ~/.config/git/config ]] || add_error "Git config file missing"

  command -v git >/dev/null 2>&1 || add_error "Git not installed"

  if command -v git >/dev/null 2>&1; then
    git config --global pull.rebase >/dev/null || add_error "Git pull.rebase not configured"
    git config --global init.defaultBranch >/dev/null || add_error "Git defaultBranch not configured"

    git config --global alias.co >/dev/null || add_error "Git alias 'co' not configured"
    git config --global alias.br >/dev/null || add_error "Git alias 'br' not configured"
    git config --global alias.ci >/dev/null || add_error "Git alias 'ci' not configured"
    git config --global alias.st >/dev/null || add_error "Git alias 'st' not configured"
  fi
}
