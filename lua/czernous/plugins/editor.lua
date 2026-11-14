-- Editing helpers. Keys for these are in keymaps.lua.
-- Each plugin loads on first use (see the trigger on each line).
return {
  {
    -- Pin a handful of files and jump between them. Loads on the first harpoon key.
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('harpoon'):setup({ settings = { save_on_toggle = true } })
    end,
  },
  -- Detect tabstop and shiftwidth automatically when a file opens.
  { 'tpope/vim-sleuth', event = { 'BufReadPre', 'BufNewFile' } },
  {
    -- Runs the project's formatter program if one is on $PATH, otherwise asks
    -- the language server. Loads on <leader>f (format.lua). :ConformInfo shows
    -- what would run for the current file.
    'stevearc/conform.nvim',
    cmd = 'ConformInfo',
    opts = function()
      -- which formatter programs to try per filetype lives in format.lua
      return { formatters_by_ft = require('czernous.format').conform_by_ft() }
    end,
  },
  -- Comment.nvim not needed: Neovim has built-in commenting.
  --   gcc = toggle line, gc{motion} / gc (visual) = toggle range.
}
