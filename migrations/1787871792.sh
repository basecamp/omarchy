echo "Retint opencode with the Omarchy theme instead of restarting it"

# omarchy-theme-set used to SIGUSR2 opencode after every theme change. That
# signal makes opencode dispose its instances, which interrupts any agent
# running in a session. The signal also predates the omarchy-theme TUI plugin,
# which watches the synced theme file and retints running sessions live
# without touching sessions.
#
# Existing installs get the plugin wired into tui.json so a plain
# `omarchy-theme-set-opencode` reaches their running sessions too. The theme
# itself is not switched here: point tui.json at "omarchy" -- the theme picker
# also lists it -- or run `omarchy-theme-set-opencode --activate` to opt in.

OPENCODE_DIR="$HOME/.config/opencode"

[[ -d $OPENCODE_DIR ]] || exit 0

plugin_source="$OMARCHY_PATH/config/opencode/tui-plugins/omarchy-theme.ts"
plugin_target="$OPENCODE_DIR/tui-plugins/omarchy-theme.ts"

if [[ -f $plugin_source ]]; then
  mkdir -p "$(dirname "$plugin_target")"
  ln -sfn "$plugin_source" "$plugin_target"
fi

tui_config="$OPENCODE_DIR/tui.json"

if [[ -f $tui_config ]]; then
  if ! jq -e --arg plugin "$plugin_target" '.plugin | index($plugin)' "$tui_config" >/dev/null 2>&1; then
    tmp=$(mktemp "$tui_config.XXXXXX")
    jq --arg plugin "$plugin_target" '.plugin = ((.plugin // []) + [$plugin] | unique)' "$tui_config" >"$tmp"
    mv "$tmp" "$tui_config"
  fi
fi

omarchy-theme-set-opencode
