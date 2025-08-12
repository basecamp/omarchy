local M = {}

-- Store the last known theme symlink target
local last_theme_target = nil

-- Check if light.mode file exists
local function check_mode()
  local mode_path = vim.fn.expand("~/.config/omarchy/current/theme/light.mode")
  return vim.fn.filereadable(mode_path) == 1
end

-- Reload the theme based on Omarchy's current theme
function M.reload_theme()
  local theme_dir = vim.fn.resolve(vim.fn.expand("~/.config/omarchy/current/theme"))
  local theme_config = theme_dir .. "/neovim.lua"

  -- Check if the theme directory has changed
  if theme_dir == last_theme_target then
    return
  end

  if vim.fn.filereadable(theme_config) == 1 then
    local ok, result = pcall(dofile, theme_config)
    if not ok then
      print("Error loading theme: " .. result)
      return
    end

    if type(result) == "table" then
      -- Look for LazyVim opts with colorscheme
      for _, entry in ipairs(result) do
        if entry[1] == "LazyVim/LazyVim" and entry.opts then
          -- Set background based on light.mode file
          vim.o.background = check_mode() and "light" or "dark"

          -- Set colorscheme
          if entry.opts.colorscheme then
            vim.cmd("hi clear")
            local colorscheme_ok, err = pcall(vim.cmd, "colorscheme " .. entry.opts.colorscheme)
            if not colorscheme_ok then
              print("Error applying colorscheme: " .. err)
              return
            end
            vim.cmd("redraw!")
            last_theme_target = theme_dir
            return
          end
        end
      end
      print("No valid colorscheme found in " .. theme_config)
    else
      print("Invalid theme config format in " .. theme_config)
    end
  else
    print("Theme config not found: " .. theme_config)
  end
end

function M.setup()
  -- Load the theme on startup
  M.reload_theme()

  -- Reload theme on custom User event
  vim.api.nvim_create_autocmd("User", {
    pattern = "OmarchyThemeReload",
    callback = M.reload_theme,
  })

  -- Set up SIGUSR1 handler
  local uv = vim.loop
  local signal = uv.new_signal()
  uv.signal_start(signal, "sigusr1", function()
    vim.schedule(function()
      vim.cmd("doautocmd User OmarchyThemeReload")
    end)
  end)
end

return M
