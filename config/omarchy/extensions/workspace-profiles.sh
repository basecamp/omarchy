# Workspace Profiles — omarchy-menu extension
#
# Copied to ~/.config/omarchy/extensions/workspace-profiles.sh by
# omarchy-setup-workspace-profiles. Overrides show_main_menu and
# go_to_menu to inject a "Workspace profiles" top-level entry. When the
# feature is disabled, the user still sees the entry — clicking any
# submenu item re-enables on demand. The main menu override preserves
# all existing entries; update if upstream omarchy-menu grows new ones.

_wp_input() {
  # Free-text prompt via walker --dmenu (empty options list). Returns
  # typed text. Called only from menu.sh handlers that already run
  # inside omarchy-menu's walker session to avoid nested-walker races.
  local prompt="$1"
  echo -n "" | omarchy-launch-walker --dmenu --width 295 --minheight 1 --maxheight 630 -p "$prompt…" 2>/dev/null
}

show_workspace_profiles_menu() {
  case $(menu "Workspace profiles" \
    "  Switch profile\n  Create profile\n  Rename profile\n  Delete profile\n  Set default\n  Set color\n  Reorder profiles\n  Disable") in
  *Switch*)
    local p; p=$(menu "Switch to" "$(omarchy-workspace-profile list)")
    [[ -n "$p" ]] && omarchy-workspace-profile set "$p"
    ;;
  *Create*)
    local n; n=$(_wp_input "New profile name")
    [[ -n "$n" ]] && omarchy-workspace-profile profile create "$n"
    ;;
  *Rename*)
    local old; old=$(menu "Rename which profile" "$(omarchy-workspace-profile list)")
    [[ -z "$old" ]] && { back_to show_main_menu; return; }
    local new; new=$(_wp_input "New name for '$old'")
    [[ -n "$new" ]] && omarchy-workspace-profile profile rename "$old" "$new"
    ;;
  *Delete*)
    local p; p=$(menu "Delete which profile" "$(omarchy-workspace-profile list)")
    [[ -z "$p" ]] && { back_to show_main_menu; return; }
    if [[ "$(menu "Really delete '$p'" "Yes\nNo")" == "Yes" ]]; then
      omarchy-workspace-profile profile delete "$p"
    fi
    ;;
  *default*)
    local p; p=$(menu "Set default profile" "$(omarchy-workspace-profile list)")
    [[ -n "$p" ]] && omarchy-workspace-profile profile default "$p"
    ;;
  *color*)
    local p; p=$(menu "Color for which profile" "$(omarchy-workspace-profile list)")
    [[ -z "$p" ]] && { back_to show_main_menu; return; }
    local palette="Blue    #7fbbb3\nGreen    #a7c080\nPurple    #d699b6\nAqua    #83c092\nRed    #e67e80\nOrange    #e69875\nYellow    #dbbc7f\nGrey    #a0a0a0\nCustom hex…"
    local choice; choice=$(menu "Color for $p" "$palette")
    [[ -z "$choice" ]] && { back_to show_main_menu; return; }
    local hex
    if [[ "$choice" == *"Custom hex"* ]]; then
      hex=$(_wp_input "Hex color for '$p' (e.g. #7fbbb3)")
    else
      hex="${choice##* }"
    fi
    [[ -n "$hex" ]] && omarchy-workspace-profile profile color "$p" "$hex"
    ;;
  *"Reorder"*)
    # Tap-to-promote: clicking a profile bumps it up one slot. Loop
    # until the user picks Done (or cancels the walker).
    while true; do
      local list; list=$(omarchy-workspace-profile list)
      local choice; choice=$(menu "Tap a profile to move it up" "$list
  Done")
      [[ -z "$choice" || "$choice" == *"Done"* ]] && break
      omarchy-workspace-profile profile move-up "$choice" >/dev/null 2>&1 || true
    done
    ;;
  *Disable*)
    local def_name; def_name=$(omarchy-workspace-profile profile list | awk '/\*/{gsub(/[>*]/,""); $1=$1; print; exit}')
    local choice; choice=$(menu "Turn off workspace profiles" \
      "Keep everything\nKeep only ${def_name} (default)\nCancel")
    case "$choice" in
      "Keep everything") omarchy-workspace-profile off --keep-all ;;
      "Keep only"*)      omarchy-workspace-profile off --keep-default ;;
    esac
    ;;
  *) back_to show_main_menu ;;
  esac
}

# Redefine main menu to include the Workspace profiles entry (after Setup).
show_main_menu() {
  go_to_menu "$(menu "Go" "󰀻  Apps\n󰧑  Learn\n󱓞  Trigger\n  Style\n  Setup\n󱂬  Workspace profiles\n󰉉  Install\n󰭌  Remove\n  Update\n  About\n  System")"
}

# Redefine dispatcher to add our case. All original top-level entries
# are preserved. Update this list if upstream omarchy-menu grows more.
go_to_menu() {
  case "${1,,}" in
  *apps*) walker -p "Launch…" ;;
  *learn*) show_learn_menu ;;
  *trigger*) show_trigger_menu ;;
  *toggle*) show_toggle_menu ;;
  *share*) show_share_menu ;;
  *background*) show_background_menu ;;
  *capture*) show_capture_menu ;;
  *style*) show_style_menu ;;
  *theme*) show_theme_menu ;;
  *screenrecord*) show_screenrecord_menu ;;
  *setup*) show_setup_menu ;;
  *power*) show_setup_power_menu ;;
  *install*) show_install_menu ;;
  *remove*) show_remove_menu ;;
  *update*) show_update_menu ;;
  *about*) show_about ;;
  *system*) show_system_menu ;;
  *workspace*profile*) show_workspace_profiles_menu ;;
  esac
}
