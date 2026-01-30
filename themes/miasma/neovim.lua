return {
  {
    "xero/miasma.nvim",
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "miasma",
    },
  },
}
-- local function has_miasma_in_user_plugins()
--     local plugins_dir = vim.fn.expand("~/.config/nvim/lua/plugins")
--     if vim.fn.isdirectory(plugins_dir) ~= 1 then
--         return false
--     end
--     local plugin_files = vim.fn.glob(plugins_dir .. "/**/*.lua", true, true)
--     for _, file in ipairs(plugin_files) do
--         local ok, lines = pcall(vim.fn.readfile, file)
--         if ok then
--             for _, line in ipairs(lines) do
--                 if line:find("xero/miasma.nvim", 1, true) then
--                     return true
--                 end
--             end
--         end
--     end
--     return false
-- end
--
-- if has_miasma_in_user_plugins() then
--   return {
--     {
--       "xero/miasma.nvim",
--       lazy = false,
--       priority = 1000,
--       config = function()
--         vim.cmd("colorscheme miasma")
--       end,
--     },
--   }
-- end
--
-- return {
--   {
--     "bjarneo/aether.nvim",
--     name = "aether",
--     priority = 1000,
--     opts = {
--       disable_italics = false,
--       colors = {
--         -- Monotone shades (base00-base07)
--         base00 = "#222222",         -- Default background
--         base01 = "#666666",         -- Lighter background (status bars)
--         base02 = "#e4c47a",         -- Selection background
--         base03 = "#666666",         -- Comments, invisibles
--         base04 = "#c2c2b0",         -- Dark foreground
--         base05 = "#c2c2b0",         -- Default foreground
--         base06 = "#d7c483",         -- Light foreground
--         base07 = "#d7c483",         -- Light background
--
--         -- Accent colors (base08-base0F)
--         base08 = "#685742",         -- Variables, errors, red
--         base09 = "#685742",         -- Integers, constants, orange
--         base0A = "#b36d43",         -- Classes, types, yellow
--         base0B = "#5f875f",         -- Strings, green
--         base0C = "#c9a554",         -- Support, regex, cyan
--         base0D = "#78824b",         -- Functions, keywords, blue
--         base0E = "#bb7744",         -- Keywords, storage, magenta
--         base0F = "#b36d43",         -- Deprecated, brown/yellow
--       },
--     },
--     config = function(_, opts)
--       require("aether").setup(opts)
--       vim.cmd.colorscheme("aether")
--
--       -- Enable hot reload
--       require("aether.hotreload").setup()
--     end,
--   },
--   {
--     "LazyVim/LazyVim",
--     opts = {
--       colorscheme = "aether",
--     },
--   },
-- }
