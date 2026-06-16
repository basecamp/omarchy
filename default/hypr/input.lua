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

local vconsole = read_vconsole()

hl.config({
  input = {
    kb_layout = vconsole.XKBLAYOUT or "us",
    kb_variant = vconsole.XKBVARIANT or "",
    kb_model = "",
    kb_options = "compose:caps",
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
