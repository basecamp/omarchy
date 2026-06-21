echo "Fix hyprland toggle load order so user overrides take precedence"

HYPR_LUA=~/.config/hypr/hyprland.lua
HYPR_CONF=~/.config/hypr/hyprland.conf

if [[ -f $HYPR_LUA ]] && grep -q 'require("default.hypr.toggles")' "$HYPR_LUA"; then
  toggle_line=$(grep -n 'require("default.hypr.toggles")' "$HYPR_LUA" | cut -d: -f1 | tail -n1)
  looknfeel_line=$(grep -n 'require("hypr.looknfeel")' "$HYPR_LUA" | cut -d: -f1 | tail -n1)
  looknfeel_line=${looknfeel_line:-0}

  if [[ -n $toggle_line ]] && (( toggle_line > looknfeel_line )); then
    python3 - "$HYPR_LUA" <<'PYTHON'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

old_block = (
    "\n-- Change your own setup in these files and override defaults.\n"
    "require(\"hypr.monitors\")\n"
    "require(\"hypr.input\")\n"
    "require(\"hypr.bindings\")\n"
    "require(\"hypr.looknfeel\")\n"
    "require(\"hypr.autostart\")\n"
    "\n-- Toggle config flags dynamically.\n"
    "require(\"default.hypr.toggles\")\n"
)
new_block = (
    "\n-- Toggle config flags dynamically (before user overrides so users can override toggle settings).\n"
    "require(\"default.hypr.toggles\")\n"
    "\n-- Change your own setup in these files and override defaults.\n"
    "require(\"hypr.monitors\")\n"
    "require(\"hypr.input\")\n"
    "require(\"hypr.bindings\")\n"
    "require(\"hypr.looknfeel\")\n"
    "require(\"hypr.autostart\")\n"
)
if old_block in content:
    with open(path, "w") as f:
        f.write(content.replace(old_block, new_block))
    print("Fixed toggle load order in ~/.config/hypr/hyprland.lua")
else:
    print("Custom hyprland.lua detected — move require(\"default.hypr.toggles\") before user require() calls manually")
PYTHON
  fi
fi

if [[ -f $HYPR_CONF ]] && grep -q 'toggles/hypr/\*\.conf' "$HYPR_CONF"; then
  toggle_line=$(grep -n 'toggles/hypr/\*\.conf' "$HYPR_CONF" | cut -d: -f1 | tail -n1)
  looknfeel_line=$(grep -n 'source.*config/hypr/looknfeel\.conf' "$HYPR_CONF" | cut -d: -f1 | tail -n1)
  looknfeel_line=${looknfeel_line:-0}

  if [[ -n $toggle_line ]] && (( toggle_line > looknfeel_line )); then
    python3 - "$HYPR_CONF" <<'PYTHON'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

old_block = (
    "\n# Change your own setup in these files (and overwrite any settings from defaults!)\n"
    "source = ~/.config/hypr/monitors.conf\n"
    "source = ~/.config/hypr/input.conf\n"
    "source = ~/.config/hypr/bindings.conf\n"
    "source = ~/.config/hypr/looknfeel.conf\n"
    "source = ~/.config/hypr/autostart.conf\n"
    "\n# Toggle config flags dynamically\n"
    "source = ~/.local/state/omarchy/toggles/hypr/*.conf\n"
)
new_block = (
    "\n# Toggle config flags dynamically (before user overrides so users can override toggle settings)\n"
    "source = ~/.local/state/omarchy/toggles/hypr/*.conf\n"
    "\n# Change your own setup in these files (and overwrite any settings from defaults!)\n"
    "source = ~/.config/hypr/monitors.conf\n"
    "source = ~/.config/hypr/input.conf\n"
    "source = ~/.config/hypr/bindings.conf\n"
    "source = ~/.config/hypr/looknfeel.conf\n"
    "source = ~/.config/hypr/autostart.conf\n"
)
if old_block in content:
    with open(path, "w") as f:
        f.write(content.replace(old_block, new_block))
    print("Fixed toggle load order in ~/.config/hypr/hyprland.conf")
else:
    print("Custom hyprland.conf detected — move 'source = ~/.local/state/omarchy/toggles/hypr/*.conf' before user source lines manually")
PYTHON
  fi
fi
