-- Theme renderer, statusline, icons, keymap popup.
return {
  -- Colour schemes. Neither is loaded at a normal start: theme.lua replays its
  -- cached result. They load only when that cache has to be rebuilt.
  { 'catppuccin/nvim', name = 'catppuccin' }, -- the default look (see theme.lua)
  -- Renders a 16-colour base16 palette supplied from outside (how Stylix themes
  -- Neovim). Not used unless $NVIM_BASE16_PALETTE is set.
  { 'nvim-mini/mini.base16' },
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
