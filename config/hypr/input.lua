-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

-- Reads the boot-time console/keyboard settings written by the installer,
-- used only as a fallback for a system that hasn't configured a layout
-- through the panel yet.
local function read_vconsole()
  local values = {}
  local file = io.open("/etc/vconsole.conf", "r")
  if not file then
    return values
  end

  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and value then
      value = value:gsub("%s+#.*$", "")
      value = value:gsub('^"(.*)"$', "%1")
      value = value:gsub("^'(.*)'$", "%1")
      values[key] = value
    end
  end

  file:close()
  return values
end

-- The keyboard panel (bin/omarchy-keyboard-layout) owns this file: it's the
-- list of layouts the user picked via "Add language" plus their chosen
-- switch shortcut. jq is already a hard dependency of the Omarchy CLI
-- scripts, so shelling out to it here is simpler and less error-prone than
-- hand-rolling JSON parsing in Lua.
local STATE_FILE = os.getenv("HOME") .. "/.local/state/omarchy/settings/keyboard.json"

-- Runs a shell command and returns its trimmed stdout, or an empty string
-- if the command couldn't even be started.
local function popen_trim(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return ""
  end
  local result = handle:read("*a") or ""
  handle:close()
  return (result:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Reads one field out of the keyboard state file via jq. Falls back
-- cleanly if the file is missing, unreadable, or the field isn't set --
-- Hyprland should never fail to start just because this file is stale
-- or hasn't been created yet.
local function state_field(jq_filter, fallback)
  local cmd = string.format("jq -r %s %q 2>/dev/null", jq_filter, STATE_FILE)
  local value = popen_trim(cmd)
  if value == "" or value == "null" then
    return fallback
  end
  return value
end

local vconsole = read_vconsole()

local kb_layout = state_field("'[.layouts[].code] | join(\",\")'", vconsole.XKBLAYOUT or "us")
local switcher = state_field("'.switcher // \"alt_shift\"'", "alt_shift")

-- The three switch-shortcut presets offered by the keyboard panel's pill
-- row, mapped to the matching xkb grp option.
local SWITCHER_OPTIONS = {
  alt_shift = "grp:alt_shift_toggle",
  ctrl_shift = "grp:ctrl_shift_toggle",
  right_alt = "grp:toggle",
}

local grp_option = SWITCHER_OPTIONS[switcher] or SWITCHER_OPTIONS.alt_shift

-- Compose is bound to the Menu key, not Caps Lock. "compose:caps" plus
-- "shift:both_capslock" was tried here -- on real hardware it broke every
-- switcher preset outright (Alt+Shift, Ctrl+Shift, Right Alt, Right Shift
-- all stopped switching), not just single-Shift capitalization as originally
-- suspected. Whatever is going on, that combination isn't safe to ship
-- alongside grp switching, so it's reverted to the working baseline.
local kb_options = "compose:menu," .. grp_option

-- Applies everything computed above as Hyprland's live input configuration.
hl.config({
  input = {
    kb_layout = kb_layout,
    -- Falls back to "" (xkb's default variant) if the system's vconsole.conf
    -- never set one, or the user hasn't customized their keyboard variant.
    kb_variant = vconsole.XKBVARIANT or "",
    kb_model = "",
    kb_options = kb_options,
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll nicely in the terminal.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
