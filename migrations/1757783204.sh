echo "Create ~/Work with ./bin in the path for contained projects"
mkdir -p "$HOME/Work"

if [ -f "$HOME/Work/.mise.toml" ]; then
  cp "$HOME/Work/.mise.toml" "$HOME/Work/.mise.toml.bak.$(date +%s)"
fi

cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml
