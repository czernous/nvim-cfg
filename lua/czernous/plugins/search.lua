-- Fuzzy finder. Keys are in keymaps.lua (group 'Files & search').
return {
  {
    'nvim-telescope/telescope.nvim',
    -- master (not the frozen 0.1.x): its previewer uses core treesitter,
    -- required for compatibility with nvim-treesitter main.
    branch = 'master',
    cmd = 'Telescope', -- also loads on the first search key (keymaps.lua)
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        -- Native fuzzy sorter; needs `make` and a C compiler at install time.
        -- (No `cond = executable('make')`: a PATH lookup on every startup costs
        -- ~100ms on slow PATHs. Without make the build fails once, at install,
        -- and Telescope falls back to its Lua sorter.)
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
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
