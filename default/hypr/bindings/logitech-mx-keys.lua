-- Logitech MX Keys / MX Keys S -- action keys
--
-- keyd (/etc/keyd/logitech-mx-keys.conf) rewrites each keyboard's chorded
-- action keys -- emoji, screenshot, dictation, lock on the MX Keys S; float
-- toggle, scratchpad, lock on the MX Keys -- to spare F14-F19, all of which
-- would otherwise land on unrelated shortcuts or nothing. The MX Keys S
-- mic-mute key already emits a bare F13. Bind them to the matching Omarchy
-- command here.
--
-- Bound by keycode (code:191..197 == F13..F19): the F13-F24 keysyms are
-- missing from many non-US keymaps, so a plain "F14" bind would never match.
--
-- That config file is installed only when install/hardware/logitech-mx-keys.sh
-- detects one of these keyboards, so its presence gates these binds. Nothing
-- else emits these keycodes and keyd rewrites only that keyboard, so no device
-- gate and no existing Omarchy binding changes are needed.

local function file_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- OMARCHY_MX_KEYS_KEYD_CONF overrides the gate path for tests.
local keyd_conf = os.getenv("OMARCHY_MX_KEYS_KEYD_CONF")
if not keyd_conf or keyd_conf == "" then
  keyd_conf = "/etc/keyd/logitech-mx-keys.conf"
end
if not file_exists(keyd_conf) then
  return
end

o.bind("code:191", "Mute microphone", "omarchy-audio-input-mute", { locked = true })
o.bind("code:192", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
o.bind("code:193", "Screenshot", "omarchy-capture-screenshot")
o.bind("code:195", "Lock system", "omarchy-system-lock")
o.bind("code:196", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind("code:197", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))

if o.cmd_present("voxtype") then
  o.bind("code:194", "Toggle dictation", "voxtype record toggle")
end
