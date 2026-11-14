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
  { 'mbbill/undotree', cmd = 'UndotreeToggle' },
  -- Detect tabstop and shiftwidth automatically when a file opens.
  { 'tpope/vim-sleuth', event = { 'BufReadPre', 'BufNewFile' } },
  -- External formatters (prettier, biome, ...) via :Neoformat.
  { 'sbdchd/neoformat', cmd = 'Neoformat' },
  -- Comment.nvim not needed: Neovim has built-in commenting.
  --   gcc = toggle line, gc{motion} / gc (visual) = toggle range.
}
