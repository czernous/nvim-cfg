--theprimeagen/asbjornhaland remaps

vim.g.mapleader = " "
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv") -- move lines up/down when highlighted
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")


vim.keymap.set("n", "Y", "yg$")
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- vim.keymap.set("n", "<leader>vwm", function()
--     require("vim-with-me").StartVimWithMe()
-- end)

-- vim.keymap.set("n", "<leader>svwm", function()
--     require("vim-with-me").StopVimWithMe()
-- end)

vim.keymap.set("x", "<leader>p", [["_dP]])

vim.keymap.set("n", "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set("n", "<leader>d", [["_d]])

vim.keymap.set("n", "<leader>f", function()
    vim.lsp.buf.format()
end)

vim.keymap.set("n", "<leader>nf", ":Neoformat <CR>")

vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")

vim.keymap.set("n", "<leader>s", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>]]")
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>")

vim.keymap.set("n", "<leader><leader>", function()
    vim.cmd("so")
end)


-- [[ Basic Keymaps ]]

-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
-- vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>vd', vim.diagnostic.open_float, { desc = '[V]iew [d]iagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })