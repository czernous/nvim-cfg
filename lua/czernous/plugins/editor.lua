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
  {
    -- A folder as an ordinary buffer: one line per file. Edit the lines to
    -- rename/move/delete, :w applies. `-` up a folder, <CR> open, g? help.
    -- Loads on <leader>pv / :Oil. Plain names, no icons (no special font needed).
    'stevearc/oil.nvim',
    cmd = 'Oil',
    opts = {
      default_file_explorer = false, -- `nvim <folder>` shows the start screen instead
      columns = {},
      view_options = { show_hidden = true },
      keymaps = { ['q'] = { 'actions.close', mode = 'n' } },
    },
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
