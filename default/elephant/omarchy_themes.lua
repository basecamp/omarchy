--
-- Dynamic Omarchy Theme Menu for Elephant/Walker
--
Name = "omarchythemes"
NamePretty = "Omarchy Themes"

-- The main function elephant will call
function GetEntries()
  local entries = {}
  local theme_dir = os.getenv("HOME") .. "/.config/omarchy/themes"

  -- First, get all theme directories
  local find_dirs_cmd = "find -L '" .. theme_dir .. "' -mindepth 1 -maxdepth 1 -type d 2>/dev/null"

  local handle = io.popen(find_dirs_cmd)
  if not handle then
    return entries
  end

  for theme_path in handle:lines() do
    local theme_name = theme_path:match(".*/(.+)$")

    if theme_name then
      -- find preview image
      local find_preview_cmd = "find -L '"
        .. theme_path
        .. "' -maxdepth 1 -type f \\( -name 'preview.png' -o -name 'preview.jpg' \\) 2>/dev/null | head -n 1"
      local preview_handle = io.popen(find_preview_cmd)
      local preview_path = nil

      if preview_handle then
        preview_path = preview_handle:read("*l")
        preview_handle:close()
      end

      -- If no preview found, use first image from backgrounds folder
      if not preview_path or preview_path == "" then
        local bg_cmd = "find -L '"
          .. theme_path
          .. "/backgrounds' -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) 2>/dev/null | head -n 1"
        local bg_handle = io.popen(bg_cmd)
        if bg_handle then
          preview_path = bg_handle:read("*l")
          bg_handle:close()
        end
      end

      if preview_path and preview_path ~= "" then
        local display_name = theme_name:gsub("_", " "):gsub("%-", " ")
        display_name = display_name:gsub("(%a)([%w_']*)", function(first, rest)
          return first:upper() .. rest:lower()
        end)
        display_name = display_name .. "  "

        table.insert(entries, {
          Text = display_name,
          Preview = preview_path,
          PreviewType = "file",
          Actions = {
            activate = "omarchy-theme-set " .. theme_name,
          },
        })
      end
    end
  end

  handle:close()
  return entries
end

