echo "Install dsh (DeepSeek Harness) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:@deepseek-ai/dsh dsh
fi
