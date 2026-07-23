-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

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

local function popen_trim(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return ""
  end
  local result = handle:read("*a") or ""
  handle:close()
  return (result:gsub("^%s+", ""):gsub("%s+$", ""))
end

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

-- The four switch-shortcut presets offered by the keyboard panel's pill
-- row, mapped to the matching xkb grp option.
local SWITCHER_OPTIONS = {
  alt_shift = "grp:alt_shift_toggle",
  ctrl_shift = "grp:ctrl_shift_toggle",
  right_alt = "grp:toggle",
  both_shift = "grp:shifts_toggle",
}

local grp_option = SWITCHER_OPTIONS[switcher] or SWITCHER_OPTIONS.alt_shift

-- Compose used to be bound to "compose:caps", which hijacks Caps Lock
-- entirely and turns it into the Compose key -- Caps Lock then never
-- toggles capitalization again, it just shows the small compose-pending
-- dot while waiting for the next key. Bind Compose to the Menu key
-- instead: it's unused by every switcher preset above, so Caps Lock keeps
-- working normally and Compose sequences (e.g. Menu, ', e -> é) still work.
local kb_options = "compose:menu," .. grp_option

hl.config({
  input = {
    kb_layout = kb_layout,
    kb_variant = "",
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
