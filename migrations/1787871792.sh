echo "Retint opencode with the Omarchy theme instead of restarting it"

# omarchy-theme-set used to SIGUSR2 opencode after every theme change. That
# signal makes opencode dispose its instances, which interrupts any agent
# running in a session. The signal also predates the omarchy-theme TUI plugin,
# which watches the synced theme file and retints running sessions live
# without touching sessions.
#
# Existing installs get the plugin wired into tui.json and are pointed at the
# Omarchy theme so desktop theme changes live-retint OpenCode, the same way
# every other themed app follows Omarchy. Pick a different theme in OpenCode
# (including "system", which is terminal-adaptive and will not follow) to opt out.

# Mirror how opencode itself finds its config directory.
OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"

[[ -d $OPENCODE_CONFIG ]] || exit 0

plugin_source="$OMARCHY_PATH/config/opencode/tui-plugins/omarchy-theme.ts"
plugin_target="$OPENCODE_CONFIG/tui-plugins/omarchy-theme.ts"

if [[ -f $plugin_source ]]; then
  mkdir -p "$(dirname "$plugin_target")"
  ln -sfn "$plugin_source" "$plugin_target"
fi

# Most existing installs have no tui.json yet. Create one that selects Omarchy
# so live retint is on from the next OpenCode start.
tui_config="$OPENCODE_CONFIG/tui.json"

if [[ -f $tui_config ]]; then
  if ! jq -e --arg plugin "$plugin_target" '.plugin | index($plugin)' "$tui_config" >/dev/null 2>&1; then
    tmp=$(mktemp "$tui_config.XXXXXX")
    # Append the plugin; set theme so this install follows the desktop.
    # Plugin order affects initialization, so never rewrite the rest of .plugin.
    jq --arg plugin "$plugin_target" \
      '.theme = "omarchy" | .plugin = ((.plugin // []) + [$plugin])' \
      "$tui_config" >"$tmp"
    mv "$tmp" "$tui_config"
  fi
elif [[ -f $plugin_target ]]; then
  cat >"$tui_config" <<EOF
{
  "\$schema": "https://opencode.ai/tui.json",
  "theme": "omarchy",
  "plugin": ["$plugin_target"]
}
EOF
fi

omarchy-theme-set-opencode
