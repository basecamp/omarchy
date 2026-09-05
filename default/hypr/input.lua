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

-- systemd translates console keymaps through this table when it can. Some
-- keymaps offered by Omarchy have no entry there, so keep their XKB spelling
-- here for the same fallback path.
local keymap_xkb_fallbacks = {
  -- The installer labels this console keymap as Azerbaijani. The console
  -- keymap itself is historically French AZERTY; keep installer intent here.
  azerty = { "az", "" },
  ["bg-cp1251"] = { "bg", "" },
  colemak = { "us", "colemak" },
  cz = { "cz", "" },
  ["de_CH-latin1"] = { "ch", "" },
  kyrgyz = { "kg", "" },
  ["no-latin1"] = { "no", "" },
  pl = { "pl", "" },
  ua = { "ua", "" },
}

local function resolve_keymap(keymap)
  if not keymap or keymap == "" then
    return nil, nil
  end

  local file = io.open("/usr/share/systemd/kbd-model-map", "r")
  if file then
    for line in file:lines() do
      local console_layout, xkb_layout, xkb_variant =
        line:match("^%s*([^#%s]+)%s+(%S+)%s+%S+%s+(%S+)")
      if console_layout == keymap then
        file:close()
        return xkb_layout, xkb_variant == "-" and "" or xkb_variant
      end
    end
    file:close()
  end

  local fallback = keymap_xkb_fallbacks[keymap]
  if fallback then
    return fallback[1], fallback[2]
  end

  return nil, nil
end

-- Layouts that can't type Latin letters. Keep in sync with the list in
-- etc/mkinitcpio.conf.d/omarchy_hooks.conf.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "

local vconsole = read_vconsole()

local kb_layout, kb_variant
if vconsole.XKBLAYOUT and vconsole.XKBLAYOUT ~= "" then
  kb_layout = vconsole.XKBLAYOUT
  kb_variant = vconsole.XKBVARIANT or ""
else
  kb_layout, kb_variant = resolve_keymap(vconsole.KEYMAP)
  kb_layout = kb_layout or "us"
  kb_variant = kb_variant or ""
end
-- CapsLock is the compose key, so Caps Lock itself has to live somewhere else.
-- Both Shifts together is the usual home for it, but it's easy to hit by
-- accident while typing. The _cancel variant sets Caps Lock the same way and
-- releases it on the next lone Shift, so a misfire clears itself.
local kb_options = "compose:caps,shift:both_capslock_cancel"

-- Hyprland resolves keybindings against the first entry in kb_layout, not the
-- layout that's currently active, so Omarchy's Latin-keysym bindings (SUPER + W
-- and friends) only fire when a Latin layout leads. Installing with a non-Latin
-- one would otherwise leave the desktop unusable.
if non_latin_layouts:find(" " .. kb_layout:match("^[^,]*") .. " ", 1, true) then
  kb_layout = "us," .. kb_layout
  kb_variant = "," .. kb_variant
  -- Reach the original layout with Left Alt + Right Alt.
  kb_options = kb_options .. ",grp:alts_toggle"
end

hl.config({
  input = {
    kb_layout = kb_layout,
    kb_variant = kb_variant,
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
o.window("(Alacritty|kitty)", { scroll_touchpad = 1.5 })
-- foot only applies its scrollback multiplier to wheel clicks, not precise touchpad scrolling.
o.window("foot", { scroll_touchpad = 2.0 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
