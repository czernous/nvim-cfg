-- Load order matters: leader + options first, then keys, then plugins.
require('czernous.options')
require('czernous.keymaps').setup()
require('czernous.lazy')
require('czernous.theme').setup()
require('czernous.statusline').setup()
-- Language servers are found and started just after the first screen is drawn.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function() vim.schedule(function() require('czernous.lsp').setup() end) end,
})
