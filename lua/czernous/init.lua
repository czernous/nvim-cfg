-- `nvim .` (or any single folder): the folder is the project to work in. It
-- becomes the working directory, and the start screen is shown instead of the
-- folder listing (<leader>pv opens the file explorer).
local start_dir = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 and vim.fn.argv(0) or nil
if start_dir then vim.cmd.cd(vim.fn.fnameescape(start_dir)) end

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
      -- separately: a problem drawing the start screen must not cost you language servers
      local ok, err = pcall(require('czernous.start').show, start_dir ~= nil)
      if not ok then vim.notify('Start screen: ' .. tostring(err), vim.log.levels.WARN) end
      require('czernous.lsp').setup()
    end)
  end,
})
