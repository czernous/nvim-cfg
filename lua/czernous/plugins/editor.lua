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
    opts = {
      -- First formatter found on $PATH wins; none found -> the language server.
      formatters_by_ft = {
        lua = { 'stylua' },
        -- JS/TS: Biome, else oxfmt (the project's own copy in node_modules first).
        -- No Prettier: slow, and superseded by these.
        javascript = { 'biome', 'oxfmt', stop_after_first = true },
        javascriptreact = { 'biome', 'oxfmt', stop_after_first = true },
        typescript = { 'biome', 'oxfmt', stop_after_first = true },
        typescriptreact = { 'biome', 'oxfmt', stop_after_first = true },
        json = { 'biome' },
        jsonc = { 'biome' },
        css = { 'biome' },
        python = { 'ruff_format', 'black', stop_after_first = true },
        nix = { 'nixfmt', 'alejandra', stop_after_first = true },
      },
    },
  },
  -- Comment.nvim not needed: Neovim has built-in commenting.
  --   gcc = toggle line, gc{motion} / gc (visual) = toggle range.
}
