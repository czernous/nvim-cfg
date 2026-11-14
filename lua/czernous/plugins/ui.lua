-- Colorschemes, statusline, icons, keymap popup.
return {
  {
    'navarasu/onedark.nvim',
    name = 'onedark',
    priority = 1000,
    config = function()
      require('onedark').setup({ style = 'warm' })
    end,
  },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'nvim-tree/nvim-web-devicons' },
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      options = {
        theme = 'onedark',
        component_separators = '|',
        section_separators = '',
      },
    },
  },
  {
    -- Press <leader> and wait: shows what the next key does.
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      spec = {
        { '<leader>c', group = '[C]ode' },
        { '<leader>d', group = '[D]ocument' },
        { '<leader>g', group = '[G]it' },
        { '<leader>h', group = 'Git [H]unk' },
        { '<leader>r', group = '[R]ename' },
        { '<leader>s', group = '[S]earch' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>w', group = '[W]orkspace' },
        { '<leader>', group = 'VISUAL <leader>', mode = 'v' },
        { '<leader>h', group = 'Git [H]unk', mode = 'v' },
      },
    },
  },
}
