--
-- Dynamic Omarchy Unlocks Menu for Elephant/Walker
--
-- A "Default" entry restores the omarchy-shipped Plymouth via
-- omarchy-plymouth-reset. After that, every theme that has a preview-unlock.png
-- appears as a customised unlock; picking one runs omarchy-plymouth-set-by-theme
-- <theme>. Both run in a floating terminal so sudo can prompt.
--
Name = "omarchyunlocks"
NamePretty = "Omarchy Unlocks"
HideFromProviderlist = true
FixedOrder = true

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")
  local user_themes_dir = home .. "/.config/omarchy/themes"
  local omarchy_path = os.getenv("OMARCHY_PATH") or ""
  local default_themes_dir = omarchy_path .. "/themes"
  local default_preview = omarchy_path .. "/default/plymouth/preview-unlock.png"

  local seen_themes = {}

  local function process_themes_from_dir(themes_dir)
    local handle = io.popen("find -L '" .. themes_dir .. "' -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    if not handle then
      return
    end

    for theme_path in handle:lines() do
      local theme_name = theme_path:match(".*/(.+)$")

      if theme_name and not seen_themes[theme_name] then
        seen_themes[theme_name] = true

        local preview_path = theme_path .. "/preview-unlock.png"

        if file_exists(preview_path) then
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
              activate = "omarchy-launch-floating-terminal-with-presentation "
                .. shell_escape("omarchy-plymouth-set-by-theme " .. shell_escape(theme_name)),
            },
          })
        end
      end
    end

    handle:close()
  end

  process_themes_from_dir(user_themes_dir)
  process_themes_from_dir(default_themes_dir)

  -- Default entry last — restores the shipped Plymouth.
  local default_entry = {
    Text = "Default  ",
    Actions = {
      activate = "omarchy-launch-floating-terminal-with-presentation "
        .. shell_escape("omarchy-plymouth-reset"),
    },
  }
  if file_exists(default_preview) then
    default_entry.Preview = default_preview
    default_entry.PreviewType = "file"
  end
  table.insert(entries, default_entry)

  return entries
end
