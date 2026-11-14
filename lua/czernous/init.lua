-- `nvim .` (or any single folder): the folder is the project to work in. It
-- becomes the working directory, and the start screen is shown instead of the
-- folder listing (<leader>pv opens the project view).
local start_dir = vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 and vim.fn.argv(0) or nil
if start_dir then vim.cmd.cd(vim.fn.fnameescape(start_dir)) end

-- The history file (ShaDa: recent files, registers, marks, command history)
-- takes 1-2.5 ms to read. Nothing on the first screen needs it, so it is read
-- just after that screen is drawn (below) instead of before it.
local shadafile = vim.o.shadafile
if shadafile ~= 'NONE' then vim.o.shadafile = 'NONE' end

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
      if shadafile ~= 'NONE' then
        vim.o.shadafile = shadafile
        pcall(vim.cmd, 'rshada!')
      end
      -- separately: a problem drawing the start screen must not cost you language servers
      local ok, err = pcall(require('czernous.start').show, start_dir ~= nil)
      if not ok then vim.notify('Start screen: ' .. tostring(err), vim.log.levels.WARN) end
      require('czernous.lsp').setup()
    end)
  end,
})

-- Extended % matching (if/else/end, HTML tags...) is only useful inside a file:
-- load it with the first one rather than at startup (~0.4 ms).
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  once = true,
  callback = function() vim.cmd.packadd('matchit') end,
})
