local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>pf', builtin.find_files, { desc = '[p]roject [f]find' })
vim.keymap.set('n', '<leader>pg', builtin.live_grep, { desc = '[p]roject [g]rep, live_grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = '[f]ind [b]uffer' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = '[f]ind [h]elp tags' })
vim.keymap.set('n', '<leader>ps', function()
    builtin.grep_string({ search = vim.fn.input("Grep > ") })
end, { desc = '[p]roject [s]earch, grep > ' })
vim.keymap.set('n', '<C-p>', builtin.find_files, {})
