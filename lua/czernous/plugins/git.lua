-- Git integration. Keys are in keymaps.lua (groups 'Git' and 'Git hunks').
return {
  { 'tpope/vim-fugitive' },
  -- :GBrowse opens the current file on GitHub (fugitive extension).
  { 'tpope/vim-rhubarb' },
  {
    -- Git change markers in the gutter + hunk actions.
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(bufnr)
        require('czernous.keymaps').gitsigns(bufnr)
      end,
    },
  },
}
