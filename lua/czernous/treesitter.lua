-- Treesitter: syntax highlighting, indentation, parsers.
-- (nvim-treesitter `main` branch: highlighting/indent come from Neovim core and
-- are switched on here per buffer.)
--
-- Parsers in M.parsers are kept installed. Any other language gets its parser
-- installed the first time you open such a file -- if the `tree-sitter` CLI is
-- on $PATH (it compiles parsers); otherwise nothing happens, silently.

local M = {}

M.parsers = {
  -- languages you write
  'go', 'gomod', 'gosum', 'rust', 'c_sharp', 'java', 'javascript', 'typescript', 'tsx', 'lua',
  -- config, docs, shell and friends
  'bash', 'c', 'cpp', 'diff', 'html', 'jsdoc', 'json', 'luadoc', 'luap', 'markdown',
  'markdown_inline', 'python', 'query', 'regex', 'sql', 'toml', 'vim', 'vimdoc', 'yaml',
}

local pending = {} -- languages currently being installed

-- Is the tree-sitter CLI available? Looked up once per $PATH value: on slow
-- $PATHs each lookup can cost ~100ms, and FileType fires for every Telescope /
-- quickfix window. (Re-checked if $PATH changes, e.g. direnv entering a devshell.)
local cli_path, has_cli
local function cli()
  if cli_path ~= vim.env.PATH then
    cli_path, has_cli = vim.env.PATH, vim.fn.executable('tree-sitter') == 1
  end
  return has_cli
end

local function start(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if pcall(vim.treesitter.start, buf) then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

--- Install a missing parser for `lang` (if possible), then start treesitter in `buf`.
local function install_then_start(lang, buf)
  if pending[lang] or not cli() then return end
  local nts = require('nvim-treesitter')
  if not vim.tbl_contains(nts.get_available(), lang) then return end
  pending[lang] = true
  nts.install(lang):await(function()
    pending[lang] = nil
    vim.schedule(function() start(buf) end)
  end)
end

function M.setup()
  local nts = require('nvim-treesitter')
  local installed = nts.get_installed()
  local missing = vim.tbl_filter(function(l) return not vim.tbl_contains(installed, l) end, M.parsers)
  if #missing > 0 and cli() then nts.install(missing) end

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('czernous_treesitter', { clear = true }),
    callback = function(ev)
      local lang = vim.treesitter.language.get_lang(ev.match)
      if not lang then return end
      if vim.treesitter.language.add(lang) then
        start(ev.buf)
      else
        install_then_start(lang, ev.buf)
      end
    end,
  })

  -- Text objects (keys are in keymaps.lua, group 'Code structure').
  require('nvim-treesitter-textobjects').setup({
    select = { lookahead = true },
    move = { set_jumps = true },
  })
end

return M
