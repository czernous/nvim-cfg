vim.g.mapleader = " " -- Space is the <leader> key (must be set before plugins load)

vim.opt.guicursor = ""
vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true


-- Disable diagnostic gutter signs (correct API; `vim.diagnostic.signs = false` was a no-op).
vim.diagnostic.config({ signs = false })

