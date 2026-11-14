-- Colour schemes, icons, keymap popup. (The statusline is built in: statusline.lua.)
return {
  -- Colour schemes. Neither is loaded at a normal start: theme.lua replays its
  -- cached result. They load only when that cache has to be rebuilt.
  { 'catppuccin/nvim', name = 'catppuccin' }, -- the default look (see theme.lua)
  -- Renders a 16-colour base16 palette supplied from outside (how Stylix themes
  -- Neovim). Not used unless $NVIM_BASE16_PALETTE is set.
  { 'nvim-mini/mini.base16' },
  { 'nvim-tree/nvim-web-devicons' },
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
