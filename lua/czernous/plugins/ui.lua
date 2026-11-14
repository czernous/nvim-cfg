-- Colorschemes, statusline, icons, keymap popup.
return {
  {
    'navarasu/onedark.nvim',
    name = 'onedark',
    lazy = false, -- the one plugin needed for the first screen
    priority = 1000,
    config = function()
      require('onedark').setup({ style = 'warm' })
    end,
  },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'nvim-tree/nvim-web-devicons' },
  {
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy', -- just after the first screen
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      options = {
        theme = 'auto', -- follow whatever theme.lua applies
        component_separators = '|',
        section_separators = '',
      },
    },
  },
  {
    -- Press <leader> and wait: shows what the next key does.
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = function()
      -- group labels come from keymaps.lua
      return { spec = require('czernous.keymaps').which_key() }
    end,
  },
}
