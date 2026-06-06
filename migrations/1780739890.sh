echo "Use delta for Git and LazyGit diffs"

omarchy-pkg-add git-delta

git_config="$HOME/.config/git/config"
lazygit_config="$HOME/.config/lazygit/config.yml"

mkdir -p "$(dirname "$git_config")" "$(dirname "$lazygit_config")"

git config --file "$git_config" --get core.pager >/dev/null || git config --file "$git_config" core.pager delta
git config --file "$git_config" --get interactive.diffFilter >/dev/null || git config --file "$git_config" interactive.diffFilter "delta --color-only"
git config --file "$git_config" --get delta.navigate >/dev/null || git config --file "$git_config" delta.navigate true

if [ ! -s "$lazygit_config" ]; then
  cp "$OMARCHY_PATH/config/lazygit/config.yml" "$lazygit_config"
fi
