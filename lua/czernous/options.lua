vim.g.mapleader = " " -- Space is the <leader> key (must be set before plugins load)

vim.opt.guicursor = ""
vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true


-- Always show the sign column, so git markers appearing doesn't shift the text.
vim.opt.signcolumn = 'yes'

-- Diagnostics: no inline (virtual) text and no gutter signs -- by choice, for
-- speed and calm. Find errors with: the counts in the statusline, underlines,
-- ]d / [d (jump + popup), <leader>vd (popup) and <leader>ttx (Trouble list).
vim.diagnostic.config({
  signs = false,
  virtual_text = false,
  severity_sort = true,
  float = { border = 'rounded', source = true },
})

