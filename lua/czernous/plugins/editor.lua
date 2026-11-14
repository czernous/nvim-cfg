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
    -- The file explorer (<leader>pv): a folder as an ordinary buffer, one line
    -- per file. Chosen on measurement: first open 34 ms vs 693 ms for Neovim's
    -- built-in explorer on this machine (which looks up half a dozen programs
    -- on $PATH when it loads); later opens under 1 ms vs 7-14 ms.
    -- Loads on <leader>pv / :Oil. Plain names, no icons (no special font needed).
    'stevearc/oil.nvim',
    cmd = 'Oil',
    opts = {
      default_file_explorer = false, -- `nvim <folder>` shows the start screen instead
      columns = {},
      view_options = { show_hidden = true },
      keymaps = { ['q'] = { 'actions.close', mode = 'n' } },
      -- A one-line reminder of the keys, at the top of the explorer window.
      win_options = {
        winbar = '%#Comment# Enter open   - up   q close   |   edit a line + :w  rename / move   dd + :w  delete   o + name + :w  new file (end with / for a folder)   g? all keys',
      },
    },
  },
  {
    -- Lists the fixes a language server offers and shows what each would change
    -- before you apply it. Loads on the first fix key (<leader>ef, gra...).
    'aznhe21/actions-preview.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim' },
    opts = {
      backend = { 'telescope' },
      telescope = { sorting_strategy = 'ascending', layout_strategy = 'vertical',
        layout_config = { width = 0.7, height = 0.8, prompt_position = 'top', preview_cutoff = 15, preview_height = function(_, _, max_lines) return max_lines - 12 end } },
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
