echo "Fix XCompose use in Typora"
if command -v typora &>/dev/null; then
  cp ~/.local/share/omarchy/applications/xtras/typora.desktop ~/.local/share/applications/
fi
