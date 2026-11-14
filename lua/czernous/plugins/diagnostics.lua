-- Trouble: a list view for diagnostics, quickfix and references.
-- Keys are in keymaps.lua (group 'Diagnostics'); pressing one loads Trouble.
return {
  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    cmd = 'Trouble',
    opts = {},
    keys = require('czernous.keymaps').lazy('trouble.nvim'),
  },
}
