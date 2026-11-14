-- Syntax highlighting, indentation and code-structure text objects.
-- Setup lives in lua/czernous/treesitter.lua; keys are in keymaps.lua.
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main', -- required for Neovim 0.12; master is archived
    event = 'FileType', -- first buffer with a filetype
    build = ':TSUpdate',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    config = function()
      require('czernous.treesitter').setup() -- parsers, highlighting, text objects
    end,
  },
  -- Shows the enclosing function/class at the top of the window.
  { 'nvim-treesitter/nvim-treesitter-context', event = { 'BufReadPre', 'BufNewFile' } },
  -- (playground removed: use built-in :InspectTree / :Inspect.)
}
