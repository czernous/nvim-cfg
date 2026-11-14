-- Fuzzy finder. Keys are in keymaps.lua (group 'Files & search').
return {
  {
    'nvim-telescope/telescope.nvim',
    -- master (not the frozen 0.1.x): its previewer uses core treesitter,
    -- required for compatibility with nvim-treesitter main.
    branch = 'master',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        -- Native fuzzy sorter; needs `make` and a C compiler.
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function() return vim.fn.executable('make') == 1 end,
      },
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          mappings = {
            i = { ['<C-u>'] = false, ['<C-d>'] = false },
          },
        },
      })
      pcall(telescope.load_extension, 'fzf')
    end,
  },
}
