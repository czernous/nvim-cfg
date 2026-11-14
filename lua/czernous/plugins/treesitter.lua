return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    branch = 'main', -- required for Neovim 0.11+/0.12; master is archived & crashes on injections
    lazy = false,
    build = ':TSUpdate',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
  },

  -- 'nvim-treesitter/playground' removed: archived and incompatible with current
  -- Neovim. Use the built-in :InspectTree and :Inspect instead.
  {
    'nvim-treesitter/nvim-treesitter-context'
  },
}
