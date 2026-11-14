-- Git integration. Keys are in keymaps.lua (groups 'Git' and 'Git hunks').
return {
  -- Loads on :Git (or <leader>gs).
  { 'tpope/vim-fugitive', cmd = { 'Git', 'G', 'Gdiffsplit', 'Gvdiffsplit', 'Gread', 'Gwrite', 'Gedit' } },
  -- :GBrowse opens the current file on GitHub (fugitive extension).
  { 'tpope/vim-rhubarb', cmd = 'GBrowse', dependencies = { 'tpope/vim-fugitive' } },
  {
    -- Git change markers in the gutter + hunk actions. Loads when a file opens.
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
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
