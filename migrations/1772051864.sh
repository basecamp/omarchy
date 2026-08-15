echo "Disable Ruby compilation in mise (if mise and ruby are installed)"

if omarchy-cmd-present mise && mise which ruby &>/dev/null; then
  mise settings set ruby.compile false
fi
