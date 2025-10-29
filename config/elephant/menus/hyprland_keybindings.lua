
name = "hyprland_keybindings"
name_pretty = "Hyprland keybindings"
icon = "applications-other"
lua = "hyprland_keybindings"
-- ensure walker calls Action(), so do NOT set action = "%VALUE%"
action = "%VALUE%"


-- Hyprland Keybindings plugin for Walker
-- Displays keybindings and executes them on selection

local keycode_map = {}

-- Build keycode to symbol mapping
local function build_keymap_cache()
	local handle = io.popen("xkbcli compile-keymap 2>/dev/null")
	if not handle then
		return
	end

	local keymap = handle:read("*a")
	handle:close()

	local code_by_name = {}
	local sym_by_name = {}
	local section = ""

	for line in keymap:gmatch("[^\r\n]+") do
		if line:match("xkb_keycodes") then
			section = "codes"
		elseif line:match("xkb_symbols") then
			section = "syms"
		elseif section == "codes" then
			local name, code = line:match("<([A-Za-z0-9_]+)>%s*=%s*(%d+)%s*;")
			if name and code then
				code_by_name[name] = code
			end
		elseif section == "syms" then
			local name, sym = line:match("key%s*<([A-Za-z0-9_]+)>%s*{%s*%[%s*([^,%s%]]+)")
			if name and sym and sym ~= "NoSymbol" then
				sym_by_name[name] = sym
			end
		end
	end

	for name, code in pairs(code_by_name) do
		local sym = sym_by_name[name]
		if sym then
			keycode_map[code] = sym
		end
	end
end

-- Convert modifier mask to text
local function modmask_to_text(mask)
	local modifiers = {
		[0] = "",
		[1] = "SHIFT",
		[4] = "CTRL",
		[5] = "SHIFT CTRL",
		[8] = "ALT",
		[9] = "SHIFT ALT",
		[12] = "CTRL ALT",
		[13] = "SHIFT CTRL ALT",
		[64] = "SUPER",
		[65] = "SUPER SHIFT",
		[68] = "SUPER CTRL",
		[69] = "SUPER SHIFT CTRL",
		[72] = "SUPER ALT",
		[73] = "SUPER SHIFT ALT",
		[76] = "SUPER CTRL ALT",
		[77] = "SUPER SHIFT CTRL ALT",
	}
	return modifiers[mask] or ""
end

-- Resolve keycode to symbol
local function resolve_keycode(keycode)
	return keycode_map[tostring(keycode)] or ""
end

function GetEntries()
	local entries = {}
	
	-- Build keycode cache
	build_keymap_cache()
	
	-- Get bindings from hyprctl
	local handle = io.popen("hyprctl -j binds 2>/dev/null")
	if not handle then
		table.insert(entries, {
			Text = "ERROR: Could not run hyprctl",
			Subtext = "hyprctl failed",
			Value = "error|||error",
		})
		return entries
	end
	
	local json_str = handle:read("*a")
	handle:close()
	
	-- Debug: Check if we got data
	if json_str == "" then
		table.insert(entries, {
			Text = "ERROR: No data from hyprctl",
			Subtext = "Empty response",
			Value = "error|||error",
		})
		return entries
	end
	
	-- Count matches found
	local match_count = 0
	
	-- Parse JSON manually (simple approach)
	-- Extract each binding object
	for binding in json_str:gmatch("{[^}]+}") do
		match_count = match_count + 1
		
		local modmask = tonumber(binding:match('"modmask"%s*:%s*(%d+)')) or 0
		local key = binding:match('"key"%s*:%s*"([^"]*)"') or ""
		local keycode = tonumber(binding:match('"keycode"%s*:%s*(%d+)')) or 0
		local description = binding:match('"description"%s*:%s*"([^"]*)"') or ""
		local dispatcher = binding:match('"dispatcher"%s*:%s*"([^"]*)"') or ""
		local arg = binding:match('"arg"%s*:%s*"([^"]*)"') or ""
		
		-- Skip empty dispatchers
		if dispatcher ~= "" then
			-- Build key combination
			local key_combo = ""
			
			-- Use keycode if key is empty
			if key == "" and keycode > 0 then
				key = resolve_keycode(keycode)
			end
			
			local mod_text = modmask_to_text(modmask)
			if mod_text ~= "" and key ~= "" then
				key_combo = mod_text .. " + " .. key
			elseif key ~= "" then
				key_combo = key
			end
			
			-- Clean up key combo
			key_combo = key_combo:gsub("^%s*+%s*", ""):gsub("%s+", " ")
			
			-- Build description if empty
			if description == "" then
				if arg ~= "" then
					description = dispatcher .. " " .. arg
				else
					description = dispatcher
				end
			end
			
			-- Clean up paths in description
			description = description:gsub("~/.local/share/omarchy/bin/", "")
			description = description:gsub("uwsm app %-%- ", "")
			description = description:gsub("uwsm%-app %-%- ", "")
			
			-- Only add if we have a valid key combo
			if key_combo ~= "" and key_combo ~= " + " then
				local value
				if arg and arg ~= "" then
					value = string.format("hyprctl dispatch %s '%s'", dispatcher, arg)
				else
					value = string.format("hyprctl dispatch %s", dispatcher)
				end

				table.insert(entries, {
					Text = description,
					Subtext = key_combo,
					Value = value
				})
			end
		
		end
	end

	return entries
end

function Action(entry)
    -- Split dispatcher and arg using our new separator
    local dispatcher, arg = entry.Value:match("^(.-)###(.*)$")

    if not dispatcher or dispatcher == "" then
        return
    end

    if dispatcher == "test" or dispatcher == "error" or dispatcher == "debug" then
        return
    end

    local cmd
    if arg and arg ~= "" then
        cmd = string.format("hyprctl dispatch %s '%s' 2>&1", dispatcher, arg)
    else
        cmd = string.format("hyprctl dispatch %s 2>&1", dispatcher)
    end

    os.execute(cmd)
end
