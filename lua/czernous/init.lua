-- `nvim .` (or any single folder): the folder is the project to work in. It
-- becomes the working directory, and the start screen is shown instead of the
-- file explorer (<leader>pv still opens that).
local start_dir = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 and vim.fn.argv(0) or nil
if start_dir then
  vim.cmd.cd(vim.fn.fnameescape(start_dir))
  -- Keep the built-in explorer from loading and taking over that folder; it is
  -- loaded on demand by <leader>pv (see explorer() in keymaps.lua).
  vim.g.loaded_netrwPlugin = 1
end

-- Load order matters: leader + options first, then keys, then plugins.
require('czernous.options')
require('czernous.keymaps').setup()
require('czernous.lazy')
require('czernous.theme').setup()
require('czernous.statusline').setup()
-- After startup: the start screen (only when no file was given), then language
-- servers are found and started. Neither delays the first screen.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      require('czernous.start').show(start_dir ~= nil)
      require('czernous.lsp').setup()
    end)
  end,
})
