-- Keyboard layout resolved from the system's /etc/vconsole.conf.
-- Shared by the user session (default/hypr/input.lua) and by the SDDM greeter
-- (default/sddm/hyprland.lua). They are separate Hyprland instances, but a
-- password is typed at one and set from the other, so both have to agree on
-- the layout.

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

-- Layouts that can't type Latin letters. Keep in sync with the list in
-- etc/mkinitcpio.conf.d/omarchy_hooks.conf.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "

local vconsole = read_vconsole()

local kb_layout = vconsole.XKBLAYOUT or "us"
local kb_variant = vconsole.XKBVARIANT or ""
-- CapsLock is the compose key, so Caps Lock itself has to live somewhere else.
-- Both Shifts together is the usual home for it, but it's easy to hit by
-- accident while typing. The _cancel variant sets Caps Lock the same way and
-- releases it on the next lone Shift, so a misfire clears itself.
local kb_options = "compose:caps,shift:both_capslock_cancel"

-- Hyprland resolves keybindings against the first entry in kb_layout, not the
-- layout that's currently active, so Omarchy's Latin-keysym bindings (SUPER + W
-- and friends) only fire when a Latin layout leads. Installing with a non-Latin
-- one would otherwise leave the desktop unusable. The greeter needs the same
-- fallback for a different reason: passwords are Latin, so a non-Latin-only
-- layout would leave the correct one untypeable at the login prompt.
if non_latin_layouts:find(" " .. kb_layout:match("^[^,]*") .. " ", 1, true) then
  kb_layout = "us," .. kb_layout
  kb_variant = "," .. kb_variant
  -- Reach the original layout with Left Alt + Right Alt.
  kb_options = kb_options .. ",grp:alts_toggle"
end

return {
  layout = kb_layout,
  variant = kb_variant,
  options = kb_options,
}
