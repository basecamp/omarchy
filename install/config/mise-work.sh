OMARCHY_DESCRIPTION="Mise"

omarchy_install() {
  # Add ./bin to path for all items in ~/Work
  mkdir -p "$HOME/Work"

  cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

  mise trust ~/Work/.mise.toml
}

omarchy_verify() {
  [[ -d "$HOME/Work" ]] || add_error "Work directory missing"

  [[ -f "$HOME/Work/.mise.toml" ]] || add_error "Mise config missing in Work directory"

  if [[ -f "$HOME/Work/.mise.toml" ]]; then
    grep -q '_.path' "$HOME/Work/.mise.toml" || add_error "Mise path configuration missing"
  fi
}
