--
-- Main Menu for Walker
--
Name = "omarchymenu_main"
NamePretty = "Omarchy Menu"
FixedOrder = true

function GetEntries()
  local entries = {}
  local def_file = os.getenv("HOME") .. "/.local/share/omarchy/bin/omarchy-menu.def"

  local f = io.open(def_file, "r")
  if not f then return entries end

  local idx = 1
  for line in f:lines() do
    if line:match("^Main\t") and not line:match("^Main\t%*") then
      local menu, label, icon, action = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
      if label and action then
        -- Translate show_*_menu functions to omarchy-menu calls
        local submenu = action:match("^show_(.+)_menu$")
        if submenu then
          action = "BACK_TO_EXIT=false omarchy-menu " .. submenu
        end

        local text = icon and icon ~= "" and (icon .. "  " .. label) or label
        table.insert(entries, {
          Text = text,
          Order = idx,
          Actions = { activate = action }
        })
        idx = idx + 1
      end
    end
  end

  f:close()

  table.sort(entries, function(a, b)
    return a.Order < b.Order
  end)

  return entries
end
