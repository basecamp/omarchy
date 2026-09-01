echo "Switch default mise tools to native lazy shims"

legacy_wrapper() {
  local command=$1 package=$2 wrapper="$HOME/.local/bin/$1"

  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || return 1
  (($(stat -c%s "$wrapper") <= 1024)) || return 1
  grep -Eqx "mise use -g( --quiet)? \"${package//./\\.}\"( \\|\\| exit 1)?" "$wrapper" || return 1
  grep -Eqx "exec (mise (x|exec) \"${package//./\\.}\" -- )?\"[^\"]+\" \"\\\$@\"" "$wrapper"
}

remove_legacy_wrapper() {
  local command=$1
  shift

  for package in "$@"; do
    if legacy_wrapper "$command" "$package"; then
      rm -f "$HOME/.local/bin/$command"
      return
    fi
  done
}

remove_legacy_wrapper codex codex aqua:openai/codex npm:@openai/codex
remove_legacy_wrapper claude claude aqua:anthropics/claude-code
remove_legacy_wrapper crush crush aqua:charmbracelet/crush
remove_legacy_wrapper agy antigravity-cli aqua:google-antigravity/antigravity-cli gemini npm:@google/gemini-cli
remove_legacy_wrapper gh gh github-cli aqua:cli/cli
remove_legacy_wrapper copilot copilot aqua:github/copilot-cli github:github/copilot-cli npm:@github/copilot
remove_legacy_wrapper opencode opencode aqua:anomalyco/opencode
remove_legacy_wrapper playwright playwright npm:playwright
remove_legacy_wrapper playwright-cli playwright npm:playwright
remove_legacy_wrapper pi pi aqua:earendil-works/pi github:earendil-works/pi npm:@earendil-works/pi-coding-agent
remove_legacy_wrapper omp oh-my-pi github:can1357/oh-my-pi
remove_legacy_wrapper grok grok npm:@xai-official/grok
remove_legacy_wrapper ghui ghui npm:@kitlangton/ghui
remove_legacy_wrapper hunk hunk aqua:modem-dev/hunk
remove_legacy_wrapper hey hey-cli github:basecamp/hey-cli
remove_legacy_wrapper ori ori github:OpenRouterLabs/ori-releases

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  MISE_CONFIG_PATH="${OMARCHY_MISE_CONFIG_PATH:-/etc/mise/config.toml}"
  sudo install -Dm644 "$OMARCHY_PATH/default/mise/config.toml" "$MISE_CONFIG_PATH"
fi

mise reshim --system
