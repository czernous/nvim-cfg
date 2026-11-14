-- Syntax highlighting, indentation and code-structure text objects.
-- nvim-treesitter `main` branch: highlighting/indent come from Neovim core and
-- are wired up here; parsers install via require('nvim-treesitter').install.
-- Keys (text objects, moves, swaps, node selection) are in keymaps.lua.
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main', -- required for Neovim 0.12; master is archived
    lazy = false,
    build = ':TSUpdate',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    config = function()
      local ts = require('nvim-treesitter')

      -- Parsers to keep installed (installs to stdpath('data')/site/parser).
      local ensure_installed = {
        'bash', 'c', 'cpp', 'diff', 'html', 'javascript', 'jsdoc', 'json',
        'lua', 'luadoc', 'luap', 'markdown', 'markdown_inline', 'python', 'query',
        'regex', 'toml', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml', 'sql',
        'c_sharp', 'rust', 'go',
      }

      -- Install only the ones that are missing (install() is async; no-op if present).
      local installed = ts.get_installed()
      local missing = vim.tbl_filter(function(lang)
        return not vim.tbl_contains(installed, lang)
      end, ensure_installed)
      if #missing > 0 then
        ts.install(missing)
      end

      -- Enable treesitter highlighting + indentation per buffer.
      -- See `:h treesitter-highlight`. vim.treesitter.start() infers the language
      -- from the buffer's filetype and no-ops (via pcall) when no parser exists.
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('czernous_treesitter', { clear = true }),
        callback = function(ev)
          if pcall(vim.treesitter.start, ev.buf) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })

      -- [[ Text objects (nvim-treesitter-textobjects, main branch) ]]
      require('nvim-treesitter-textobjects').setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })
    end,
  },
  -- Shows the enclosing function/class at the top of the window.
  { 'nvim-treesitter/nvim-treesitter-context' },
  -- (playground removed: use built-in :InspectTree / :Inspect.)
}
