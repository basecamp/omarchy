Name = "hyprland_keybindings"
NamePretty = "Hyprland keybindings"
Icon = "applications-other"
Action = "%VALUE%"
Cache = false

-- Hyprland Keybindings plugin for Walker
-- Displays keybindings and executes them on selection

local keycode_map = {}
local LOG_FILE = "/tmp/walker_hyprland_plugin.log"

--[[
-- Helper function to write messages to a log file for debugging.
--]]
local function log_message(message)
    local logfile = io.open(LOG_FILE, "a") -- Open in append mode
    if logfile then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        logfile:write(string.format("[%s] %s\n", timestamp, message))
        logfile:close()
    end
end

-- Build keycode to symbol mapping
local function build_keymap_cache()
	local handle = io.popen("xkbcli compile-keymap 2>/dev/null")
	if not handle then
        log_message("ERROR: Failed to run 'xkbcli compile-keymap'")
		return
	end
	local keymap = handle:read("*a")
	handle:close()
	local code_by_name = {}
	local sym_by_name = {}
	local section = ""
	for line in keymap:gmatch("[^\r\n]+") do
		if line:match("xkb_keycodes") then section = "codes"
		elseif line:match("xkb_symbols") then section = "syms"
		elseif section == "codes" then
			local name, code = line:match("<([A-Za-z0-9_]+)>%s*=%s*(%d+)%s*;")
			if name and code then code_by_name[name] = code end
		elseif section == "syms" then
			local name, sym = line:match("key%s*<([A-Za-z0-9_]+)>%s*{%s*%[%s*([^,%s%]]+)")
			if name and sym and sym ~= "NoSymbol" then sym_by_name[name] = sym end
		end
	end
	for name, code in pairs(code_by_name) do
		local sym = sym_by_name[name]
		if sym then keycode_map[code] = sym end
	end
end

-- Convert modifier mask to text
local function modmask_to_text(mask)
	local modifiers = {
		[0] = "", [1] = "SHIFT", [4] = "CTRL", [5] = "SHIFT CTRL", [8] = "ALT", [9] = "SHIFT ALT",
		[12] = "CTRL ALT", [13] = "SHIFT CTRL ALT", [64] = "SUPER", [65] = "SUPER SHIFT",
		[68] = "SUPER CTRL", [69] = "SUPER SHIFT CTRL", [72] = "SUPER ALT", [73] = "SUPER SHIFT ALT",
		[76] = "SUPER CTRL ALT", [77] = "SUPER SHIFT CTRL ALT",
	}
	return modifiers[mask] or ""
end

-- Resolve keycode to symbol
local function resolve_keycode(keycode)
	return keycode_map[tostring(keycode)] or ""
end

function GetEntries()
    log_message("\n--- GetEntries started ---")
	local entries = {}
	build_keymap_cache()

	local handle = io.popen("hyprctl -j binds 2>/dev/null")
	if not handle then
        log_message("ERROR: Could not execute 'hyprctl -j binds'. Is hyprctl in your PATH?")
		table.insert(entries, { Text = "ERROR: Could not run hyprctl", Subtext = "hyprctl failed", Value = "notify-send 'Hyprctl failed'" })
		return entries
	end

	local json_str = handle:read("*a")
	handle:close()

	if json_str == "" then
        log_message("ERROR: 'hyprctl -j binds' returned an empty string.")
		table.insert(entries, { Text = "ERROR: No data from hyprctl", Subtext = "Empty response", Value = "notify-send 'No data from hyprctl'" })
		return entries
	end

    log_message("Successfully read data from hyprctl. Parsing bindings...")
	for binding in json_str:gmatch("{[^}]+}") do
		local modmask = tonumber(binding:match('"modmask"%s*:%s*(%d+)')) or 0
		local key = binding:match('"key"%s*:%s*"([^"]*)"') or ""
		local keycode = tonumber(binding:match('"keycode"%s*:%s*(%d+)')) or 0
		local description = binding:match('"description"%s*:%s*"([^"]*)"') or ""
		local dispatcher = binding:match('"dispatcher"%s*:%s*"([^"]*)"') or ""
		local arg = binding:match('"arg"%s*:%s*"(.-)"%s*[,}]') or ""

		if dispatcher ~= "" then
			local key_combo = ""
			if key == "" and keycode > 0 then key = resolve_keycode(keycode) end
			
            -- THE FIX IS HERE: Changed 'mask' to 'modmask'
            local mod_text = modmask_to_text(modmask)
			
            if mod_text ~= "" and key ~= "" then key_combo = mod_text .. " + " .. key elseif key ~= "" then key_combo = key end
			key_combo = key_combo:gsub("^%s*+%s*", ""):gsub("%s+", " ")

			if description == "" then
				if arg ~= "" then description = dispatcher .. " " .. arg:gsub('\\"', '"') else description = dispatcher end
			end
			description = description:gsub("~/.local/share/omarchy/bin/", ""):gsub("uwsm app %-%- ", ""):gsub("uwsm%-app %-%- ", "")

			if key_combo ~= "" and key_combo ~= " + " then
				local cmd
				log_message(string.format("Processing binding: Subtext='%s', dispatcher='%s', arg='%s'", key_combo, dispatcher, arg))
				
                if dispatcher == "exec" and arg ~= "" then
					local clean_arg = arg:gsub('\\"', '"')
					local quoted_arg = "'" .. clean_arg:gsub("'", "'\\''") .. "'"
					cmd = "hyprctl dispatch exec " .. quoted_arg
				elseif arg ~= "" then
					cmd = string.format("hyprctl dispatch %s %s", dispatcher, arg)
				else
					cmd = string.format("hyprctl dispatch %s", dispatcher)
				end
				
                log_message(string.format(" -> Generated command: %s", cmd))
				table.insert(entries, { Text = description, Subtext = key_combo, Value = cmd })
			end
		end
	end
    log_message(string.format("--- GetEntries finished. Found %d valid entries. ---", #entries))
	return entries
end