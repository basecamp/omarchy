#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# Load every default binding and print one normalized line per bind:
# signature, keys as written, description. The signature sorts modifiers and
# resolves code:N to the keysym it produces, so "SUPER + code:10" and
# "SUPER + 1" collide the way they do on a real keyboard.
list_bindings() {
  local home="$1"
  local epilogue="${2:-}"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_BINDING_EPILOGUE="$epilogue" lua <<'LUA'
package.path = os.getenv("HOME") .. "/.config/?.lua;" .. os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

local bindings = {}
local drag_threshold
local dsp = proxy()
dsp.exec_cmd = function(command)
  return { command = command }
end

hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    table.insert(bindings, {
      keys = keys,
      description = opts.description or "(no description)",
      release = opts.release == true,
      click = opts.click == true,
      drag = opts.drag == true,
      command = type(dispatcher) == "table" and dispatcher.command or nil,
    })
  end,
  config = function(options)
    if options.binds and options.binds.drag_threshold then
      drag_threshold = options.binds.drag_threshold
    end
  end,
  env = function() end,
  monitor = function() end,
  window_rule = function() end,
  workspace_rule = function() end,
  layer_rule = function() end,
  gesture = function() end,
  animation = function() end,
  curve = function() end,
  exec_cmd = function() end,
  dispatch = function() end,
  on = function() end,
  timer = function() end,
  get_config = function() return nil end,
  get_active_window = function() return nil end,
}, {
  __index = function()
    return function()
      return {}
    end
  end,
})

require("default.hypr.omarchy")

local epilogue = os.getenv("OMARCHY_BINDING_EPILOGUE") or ""
if epilogue ~= "" then
  assert(load(epilogue))()
end

-- X11 keycodes are evdev codes plus 8. Only the rows Omarchy binds by code
-- need naming; anything else keeps its code: form and still compares exactly.
local keycode_keysyms = {
  [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5",
  [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
  [20] = "MINUS", [21] = "EQUAL",
  [34] = "BRACKETLEFT", [35] = "BRACKETRIGHT",
  [47] = "SEMICOLON", [48] = "APOSTROPHE", [49] = "GRAVE", [51] = "BACKSLASH",
  [59] = "COMMA", [60] = "PERIOD", [61] = "SLASH",
}

local function signature(binding)
  local parts = {}
  for raw in (binding.keys .. "+"):gmatch("([^+]*)%+") do
    local part = raw:match("^%s*(.-)%s*$")
    if part ~= "" then
      table.insert(parts, part)
    end
  end

  local key = table.remove(parts) or ""
  local code = tonumber(key:match("^[Cc][Oo][Dd][Ee]:(%d+)$") or "")
  if code and keycode_keysyms[code] then
    key = keycode_keysyms[code]
  end

  for index, modifier in ipairs(parts) do
    parts[index] = modifier:upper()
  end
  table.sort(parts)
  table.insert(parts, key:upper())

  -- Release, click, and drag binds can share a chord with their complements,
  -- so each flavor keeps its own signature the way release always has.
  local flavor = (binding.release and " (release)")
    or (binding.click and " (click)")
    or (binding.drag and " (drag)")
    or ""

  return table.concat(parts, "+") .. flavor
end

for _, binding in ipairs(bindings) do
  print(signature(binding) .. "\t" .. binding.keys .. "\t" .. binding.description .. "\t" .. (binding.command or ""))
end
print("CONFIG\tbinds.drag_threshold\t" .. tostring(drag_threshold))
LUA
}

duplicate_signatures() {
  cut -f1 | sort | uniq -d
}

# Deliberate stacking: Hyprland runs both dispatchers, so cycling to the next
# window also raises it. Anything else sharing a chord is a collision.
allowed_duplicates=(
  "ALT+SHIFT+TAB"
  "ALT+TAB"
)

is_allowed_duplicate() {
  local signature="$1" allowed

  for allowed in "${allowed_duplicates[@]}"; do
    [[ $signature == "$allowed" ]] && return 0
  done

  return 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# A fresh home keeps the preinstalled app bindings on, and a stub Voxtype adds
# its conditional ones, so the check covers the largest set a user can get.
home="$tmpdir/home"
stub_bin="$tmpdir/bin"
mkdir -p "$home" "$stub_bin"
touch "$stub_bin/voxtype"
chmod +x "$stub_bin/voxtype"

bindings=$(PATH="$stub_bin:$PATH" list_bindings "$home")
[[ -n $bindings ]] || fail "default bindings load for the conflict check"

grep -Fq $'SUPER + RETURN\tTerminal' <<<"$bindings" || fail "conflict check sees the essential bindings"
grep -Fq $'SUPER + SHIFT + A\tChatGPT' <<<"$bindings" || fail "conflict check sees the preinstalled bindings"
grep -Fq $'F9\tStart dictation (push-to-talk)' <<<"$bindings" || fail "conflict check sees the Voxtype bindings"
pass "conflict check covers the full default binding set"

duplicates=$(duplicate_signatures <<<"$bindings")

while read -r signature; do
  [[ -n $signature ]] || continue
  is_allowed_duplicate "$signature" && continue
  fail "no two default bindings claim the same chord" \
    "$(awk -F'\t' -v signature="$signature" '$1 == signature { print $2 " -> " $3 }' <<<"$bindings")"
done <<<"$duplicates"
pass "no two default bindings claim the same chord"

for allowed in "${allowed_duplicates[@]}"; do
  grep -Fqx "$allowed" <<<"$duplicates" ||
    fail "every allowed duplicate chord is still stacked on purpose" "$allowed"
done
pass "allowed duplicate chords are still stacked on purpose"

# The press and release halves of a push-to-talk key are separate binds, not a
# collision.
(( $(grep -c $'^F9\t' <<<"$bindings") == 1 )) ||
  fail "press and release bindings on one key do not read as a conflict"
(( $(grep -c $'^F9 (release)\t' <<<"$bindings") == 1 )) ||
  fail "release bindings keep their own signature"
pass "press and release bindings on one key do not read as a conflict"
grep -Fqx $'CONFIG\tbinds.drag_threshold\t8' <<<"$bindings" ||
  fail "Super+left uses the expected click-versus-drag threshold"
pass "Super+left uses an eight-pixel drag threshold"

# Super+left carries two complementary binds on one chord: dragging moves the
# window, a plain click opens the link under the cursor. Exactly one of each
# flavor, or the gesture stops being a gesture.
(( $(grep -c $'^SUPER+MOUSE:272 (click)\t' <<<"$bindings") == 1 )) ||
  fail "Super+left has exactly one click binding"
(( $(grep -c $'^SUPER+MOUSE:272 (drag)\t' <<<"$bindings") == 1 )) ||
  fail "Super+left has exactly one drag binding"
(( $(grep -c $'^SUPER+MOUSE:272\t' <<<"$bindings") == 0 )) ||
  fail "Super+left carries no unflavored mouse binding"
grep -Fq $'SUPER+MOUSE:272 (drag)\tSUPER + mouse:272\tMove window' <<<"$bindings" ||
  fail "the Super+left drag moves the window"
grep -Fq $'SUPER+MOUSE:272 (click)\tSUPER + mouse:272\tOpen link in terminal\tomarchy-terminal-open-link' <<<"$bindings" ||
  fail "the Super+left click runs the terminal link helper"
pass "Super+left is one drag and one click binding"

# Guard the guard: a keysym that lands on an already bound keycode has to be
# caught, or the check above passes by simply not looking.
probe=$(PATH="$stub_bin:$PATH" list_bindings "$home" \
  'o.bind("SUPER + 1", "Conflict probe", "true")' | duplicate_signatures)
grep -Fqx "SUPER+1" <<<"$probe" ||
  fail "the conflict check catches a keysym colliding with a bound keycode"

# Modifier order is cosmetic; Hyprland binds the same chord either way.
probe=$(PATH="$stub_bin:$PATH" list_bindings "$home" \
  'o.bind("SUPER + ALT + SHIFT + RIGHT", "Conflict probe", "true")' | duplicate_signatures)
grep -Fqx "ALT+SHIFT+SUPER+RIGHT" <<<"$probe" ||
  fail "the conflict check ignores modifier order"
pass "the conflict check catches collisions across keycodes and modifier order"

# The flavor suffixes must narrow the check, not blunt it: two binds of the
# same flavor on one chord are still a collision.
probe=$(PATH="$stub_bin:$PATH" list_bindings "$home" \
  'o.bind("SUPER + mouse:272", "Conflict probe", "true", { mouse = true, click = true })' | duplicate_signatures)
grep -Fqx "SUPER+MOUSE:272 (click)" <<<"$probe" ||
  fail "the conflict check catches two same-flavor mouse bindings on one chord"
pass "the conflict check catches two same-flavor mouse bindings on one chord"
