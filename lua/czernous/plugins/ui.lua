-- Colour schemes and the keymap popup. (The statusline is built in: statusline.lua.)
return {
  -- Colour schemes. Neither is loaded at a normal start: theme.lua replays its
  -- cached result. They load only when that cache has to be rebuilt.
  { 'catppuccin/nvim', name = 'catppuccin' }, -- the default look (see theme.lua)
  -- Renders a 16-colour base16 palette supplied from outside (how Stylix themes
  -- Neovim). Not used unless $NVIM_BASE16_PALETTE is set.
  { 'nvim-mini/mini.base16' },
  {
    -- Press <leader> and wait: shows what the next key does.
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = function()
      return {
        spec = require('czernous.keymaps').which_key(), -- group labels come from keymaps.lua
        -- Plain text only (no icon font needed): keys are written out as words.
        icons = {
          mappings = false,
          rules = false,
          breadcrumb = '>',
          separator = '-',
          group = '+',
          ellipsis = '...',
          keys = {
            Up = '<Up> ', Down = '<Down> ', Left = '<Left> ', Right = '<Right> ', C = 'Ctrl-', M = 'Alt-', D = 'Cmd-',
            S = 'Shift-', CR = 'Enter ', Esc = 'Esc ', ScrollWheelDown = '<WheelDown> ', ScrollWheelUp = '<WheelUp> ',
            NL = 'Enter ', BS = 'Backspace ', Space = 'Space ', Tab = 'Tab ', F1 = 'F1', F2 = 'F2', F3 = 'F3', F4 = 'F4',
            F5 = 'F5', F6 = 'F6', F7 = 'F7', F8 = 'F8', F9 = 'F9', F10 = 'F10', F11 = 'F11', F12 = 'F12',
          },
        },
      }
    end,
  },
}
