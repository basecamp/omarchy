--
-- Dynamic Omarchy Theme Menu for Elephant/Walker
--
Name = "omarchythemes"
NamePretty = "Omarchy Themes"

-- The main function elephant will call
function GetEntries()
    local entries = {}
    local theme_dir = os.getenv("HOME").. "/.config/omarchy/themes"

    local find_cmd = "find -L '"..
        theme_dir..
        "' -maxdepth 2 -type f \\( -name 'preview.png' -o -name 'preview.jpg' \\) 2>/dev/null"

    local handle = io.popen(find_cmd)
    if not handle then
        return entries
    end

    for file_path in handle:lines() do
        local theme_name = file_path:match(".*/(.-)/[^/]+$")

        if theme_name then
            table.insert(entries, {
                Text = theme_name,

                Preview = file_path,
                PreviewType = "file",

                Actions = {
                    activate = "omarchy-theme-set ".. theme_name
                }
            })
        end
    end

    handle:close()
    return entries
end