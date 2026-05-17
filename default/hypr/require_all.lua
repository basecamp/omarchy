-- Require every *.lua file in a directory in sorted order.
-- Used for Omarchy extension-style folders such as default/hypr/apps,
-- default/hypr/bindings, and ~/.local/state/omarchy/toggles/hypr.
-- Pass a module prefix for normal package.path modules, e.g.
--   require_all.files(paths.omarchy_path .. "/default/hypr/apps", "default.hypr.apps")
-- Pass nil as the prefix when the directory itself has been added to package.path.

local M = {}

local function shell_quote(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

function M.files(dir, module_prefix, options)
  local handle = io.popen("find " .. shell_quote(dir) .. " -maxdepth 1 -type f -name '*.lua' -printf '%f\\n' 2>/dev/null | sort")
  if handle then
    for filename in handle:lines() do
      local module = filename:gsub("%.lua$", "")
      if module_prefix then
        module = module_prefix .. "." .. module
      end

      if options and options.reload then
        package.loaded[module] = nil
      end

      require(module)
    end
    handle:close()
  end
end

return M
