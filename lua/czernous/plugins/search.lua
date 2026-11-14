-- Fuzzy finder. Keys are in keymaps.lua (group 'Files & search').
return {
  {
    'nvim-telescope/telescope.nvim',
    -- master (not the frozen 0.1.x): its previewer uses core treesitter,
    -- required for compatibility with nvim-treesitter main.
    branch = 'master',
    cmd = 'Telescope', -- also loads on the first search key (keymaps.lua)
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          -- no file-type icons (they need a special font); plain names
          disable_devicons = true,
          prompt_prefix = '> ',
          selection_caret = '> ',
          entry_prefix = '  ',
          mappings = {
            i = { ['<C-u>'] = false, ['<C-d>'] = false },
          },
        },
      })
    end,
  },
}
