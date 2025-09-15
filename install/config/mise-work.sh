# Add ./bin to path for all items in ~/Work
mkdir -p "$HOME/Work"

cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml
