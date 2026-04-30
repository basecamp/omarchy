echo "Replace deprecated sainnhe.everforest VSCode extension with reesew.everforest-theme"

# Background:
#   The original "sainnhe.everforest" extension is no longer maintained — its
#   upstream repo (https://github.com/sainnhe/everforest-vscode) was archived
#   by the author, so it receives no updates or fixes.
#   "reesew.everforest-theme" is a maintained fork of that same extension,
#   published from https://github.com/reese/everforest-vscode, and is the
#   replacement we now ship in themes/everforest/vscode.json.


# For each VS Code variant, uninstall the old extension and re-apply theme if the
# current Omarchy theme is everforest (which will install the new extension automatically).

uninstall_old_extension() {
  local editor_cmd="$1"

  omarchy-cmd-present "$editor_cmd" || return 0

  if "$editor_cmd" --list-extensions | grep -Fxq "sainnhe.everforest"; then
    "$editor_cmd" --uninstall-extension sainnhe.everforest >/dev/null
  fi
}

uninstall_old_extension "code"
uninstall_old_extension "code-insiders"
uninstall_old_extension "codium"
uninstall_old_extension "cursor"

# If the user is currently on the everforest theme, refresh it so the updated
# vscode.json (with reesew.everforest-theme) is copied into ~/.config/omarchy/current/theme,
# then omarchy-theme-set-vscode (called by the refresh) installs the new extension.
THEME_NAME_PATH="$HOME/.config/omarchy/current/theme.name"
if [[ -f $THEME_NAME_PATH ]] && [[ "$(cat "$THEME_NAME_PATH")" == "everforest" ]]; then
  omarchy-theme-refresh
fi
