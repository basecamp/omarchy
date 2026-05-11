--
-- Dynamic Omarchy Theme Marketplace Menu for Elephant/Walker
--
Name = "omarchyThemeMarketplace"
NamePretty = "Omarchy Theme Marketplace"
HideFromProviderlist = true
Cache = false

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

local function split_tsv(line)
  local fields = {}
  local start = 1

  for _ = 1, 4 do
    local tab = line:find("\t", start, true)
    if not tab then
      return fields
    end

    table.insert(fields, line:sub(start, tab - 1))
    start = tab + 1
  end

  table.insert(fields, line:sub(start))
  return fields
end

local function load_installed_themes()
  local installed = {}
  local home = os.getenv("HOME")
  local omarchy_path = os.getenv("OMARCHY_PATH") or ""
  local dirs = {
    home .. "/.config/omarchy/themes",
  }

  if omarchy_path ~= "" then
    table.insert(dirs, omarchy_path .. "/themes")
  end

  for _, dir in ipairs(dirs) do
    local handle = io.popen("find -L " ..
      shell_escape(dir) .. " -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null")
    if handle then
      for theme_name in handle:lines() do
        installed[theme_name] = true
      end
      handle:close()
    end
  end

  return installed
end

function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")
  local cache_dir = home .. "/.cache/omarchy/theme-marketplace"
  local cache_file = cache_dir .. "/themes.tsv"
  local placeholder_preview = cache_dir .. "/fetching-preview.jpg"
  local installed_themes = load_installed_themes()

  local handle = io.open(cache_file, "r")
  if not handle then
    return {
      {
        Text = "Marketplace unavailable ",
        Actions = {
          activate = "omarchy-theme-marketplace-refresh",
        },
      },
    }
  end

  for line in handle:lines() do
    local fields = split_tsv(line)

    if #fields == 5 then
      local theme_name = fields[1]
      local name = fields[2]
      local repo_url = fields[3]
      local preview_path = fields[5]

      if theme_name ~= "" and name ~= "" and repo_url ~= "" and preview_path ~= "" then
        local installed = installed_themes[theme_name] == true
        local text = installed and (name .. "  [installed]") or (name .. "  ")
        local action = installed
            and ("omarchy-theme-set " .. shell_escape(theme_name))
            or ("omarchy-theme-marketplace-install " .. shell_escape(repo_url) .. " " .. shell_escape(name))

        local entry = {
          Text = text,
          Actions = {
            activate = action,
          },
        }

        if file_exists(preview_path) then
          entry.Preview = preview_path
          entry.PreviewType = "file"
        elseif file_exists(placeholder_preview) then
          entry.Preview = placeholder_preview
          entry.PreviewType = "file"
        end

        table.insert(entries, entry)
      end
    end
  end

  handle:close()
  return entries
end
