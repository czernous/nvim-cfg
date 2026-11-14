vim.g.mapleader = " " -- Space is the <leader> key (must be set before plugins load)

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true



-- Always show the sign column, so git markers appearing doesn't shift the text.
vim.opt.signcolumn = 'yes'

-- One border style for every popup (hover, completion docs, pickers...). With a
-- transparent UI the border is what separates a popup from the code behind it.
vim.opt.winborder = 'rounded'

-- No `~` markers on the empty lines after the end of a file.
vim.opt.fillchars:append({ eob = ' ' })

-- The built-in file explorer (netrw) is not used: <leader>pv opens oil.nvim.
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1

vim.opt.undofile = true        -- undo history survives closing the file
vim.opt.ignorecase = true      -- searching ignores case...
vim.opt.smartcase = true       -- ...unless you type a capital letter
vim.opt.scrolloff = 8          -- keep 8 lines of context around the cursor
vim.opt.splitright = true      -- new side-by-side windows open on the right
vim.opt.splitbelow = true      -- new stacked windows open below
vim.opt.inccommand = 'split'   -- :s/old/new/ shows a live preview while you type
vim.opt.cursorline = true      -- faint highlight on the line the cursor is on
vim.opt.confirm = true         -- ask "save changes?" instead of refusing to quit
vim.opt.updatetime = 300       -- "the cursor has rested" after 0.3 s (used for the statusline's `fix` hint)
