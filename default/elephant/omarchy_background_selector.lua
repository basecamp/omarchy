Name = "omarchyBackgroundSelector"
NamePretty = "Omarchy Background Selector"
Icon = "applications-other"
Cache = true
HideFromProviderlist = false
Description = "lua test menu"
SearchName = true

function GetEntries()
  local entries = {}
  local wallpaper_dir = os.getenv("HOME") .. "/.config/omarchy/current/theme/backgrounds"
  local handle = io.popen(
    "find '"
    .. wallpaper_dir
    ..
    "' -maxdepth 1 -type f -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' -o -name '*.bmp' -o -name '*.webp' 2>/dev/null"
  )
  if handle then
    for background in handle:lines() do
      local filename = background:match("([^/]+)$")
      if filename then
        table.insert(entries, {
          Text = filename,
          Subtext = "wallpaper",
          Value = background,
          Actions = {
            activate = "ln -sf '"
                .. background
                .. "' "
                .. os.getenv("HOME")
                .. "/.config/themes/current/background && killall swaybg 2>/dev/null ; swaybg -o '*' -i '"
                .. background
                .. "' -m fill &",
          },
          Preview = background,
          PreviewType = "file",
          Icon = background,
        })
      end
    end
    handle:close()
  end
  return entries
end
