-- Editing helpers. Keys for these are in keymaps.lua.
return {
  {
    -- Pin a handful of files and jump between them.
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('harpoon'):setup({ settings = { save_on_toggle = true } })
    end,
  },
  { 'mbbill/undotree' },
  -- Detect tabstop and shiftwidth automatically.
  { 'tpope/vim-sleuth' },
  -- External formatters (prettier, biome, ...) via :Neoformat.
  { 'sbdchd/neoformat' },
  -- Comment.nvim not needed: Neovim has built-in commenting.
  --   gcc = toggle line, gc{motion} / gc (visual) = toggle range.
}
