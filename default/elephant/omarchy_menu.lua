--
-- Global Search Menu for Walker
-- Parses omarchy-menu.def (excludes Main menu)
--
Name = "omarchymenu_global"
NamePretty = "Omarchy Global Search"
FixedOrder = true

function GetEntries()
  local entries = {}
  local def_file = os.getenv("HOME") .. "/.local/share/omarchy/bin/omarchy-menu.def"

  local f = io.open(def_file, "r")
  if not f then return entries end

  -- First pass: build parent map from back navigation entries
  local parents = {}
  for line in f:lines() do
    if not line:match("^#") and not line:match("^%s*$") then
      local menu, label, icon, action = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
      if label == "*" and action then
        -- Extract parent menu name from show_xxx_menu action
        local parent = action:match("show_(.+)_menu")
        if parent then
          -- Convert snake_case to PascalCase menu name
          parent = parent:gsub("^%l", string.upper):gsub("_%l", function(s) return s:sub(2):upper() end)
          parents[menu] = parent
        elseif action == "exit" then
          parents[menu] = nil
        end
      end
    end
  end

  -- Build breadcrumb for a menu
  local function get_breadcrumb(menu)
    local crumbs = {}
    local current = menu
    while current and current ~= "Main" do
      table.insert(crumbs, 1, current)
      current = parents[current]
    end
    return table.concat(crumbs, " › ")
  end

  -- Second pass: collect all non-Main, non-navigation entries
  f:seek("set", 0)
  local idx = 1
  for line in f:lines() do
    if not line:match("^#") and not line:match("^%s*$") then
      local menu, label, icon, action = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
      if menu and menu ~= "Main" and label and label ~= "*" and action then
        -- Skip entries that just navigate to submenus
        if not action:match("^show_.*_menu$") then
          local breadcrumb = get_breadcrumb(menu)
          local title = breadcrumb .. " > " .. label
          local text = icon and icon ~= "" and (icon .. "  " .. title) or title
          table.insert(entries, {
            Text = text,
            Order = idx,
            Actions = { activate = action }
          })
          idx = idx + 1
        end
      end
    end
  end

  f:close()
  return entries
end
