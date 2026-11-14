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

-- One border style for every popup (hover, completion docs, pickers...). With a
-- transparent UI the border is what separates a popup from the code behind it.
vim.opt.winborder = 'rounded'

-- No `~` markers on the empty lines after the end of a file.
vim.opt.fillchars:append({ eob = ' ' })

-- The built-in file explorer (<leader>pv) without its help banner on top.
vim.g.netrw_banner = 0
