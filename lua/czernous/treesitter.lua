-- Treesitter: syntax highlighting, indentation, parsers.
-- (nvim-treesitter `main` branch: highlighting/indent come from Neovim core and
-- are switched on here per buffer.)
--
-- Parsers in M.parsers are kept installed. Any other language gets its parser
-- installed the first time you open such a file -- if the `tree-sitter` CLI is
-- on $PATH (it compiles parsers). Missing prerequisites are reported once.

local M = {}

M.parsers = {
  -- languages you write
  'go', 'gomod', 'gosum', 'rust', 'c_sharp', 'java', 'javascript', 'typescript', 'tsx', 'lua',
  -- config, docs, shell and friends
  'bash', 'c', 'cmake', 'cpp', 'diff', 'html', 'jsdoc', 'json', 'luadoc', 'luap', 'markdown',
  'markdown_inline', 'python', 'query', 'regex', 'sql', 'toml', 'vim', 'vimdoc', 'yaml',
}

local pending = {} -- languages currently being installed
local managed = {} -- parser/query bundles installed by this plugin
local reported = {}
local function report_once(key, message, level)
  if reported[key] then return end
  reported[key] = true
  vim.notify(message, level or vim.log.levels.WARN)
end

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
  local ok, err = pcall(vim.treesitter.start, buf)
  if ok then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  else
    report_once('start:' .. vim.bo[buf].filetype, 'Syntax highlighting could not start: ' .. tostring(err) .. '\nRun :checkhealth czernous.', vim.log.levels.ERROR)
  end
end

--- Install a missing parser for `lang` (if possible), then start treesitter in `buf`.
local function install_then_start(lang, buf)
  if pending[lang] then return true end
  local nts = require('nvim-treesitter')
  if not vim.tbl_contains(nts.get_available(), lang) then
    report_once('unsupported:' .. lang, 'No configured syntax parser for ' .. lang .. '; syntax highlighting is unavailable.')
    return false
  end
  if not cli() then
    report_once('cli:' .. lang, 'Syntax support for ' .. lang .. ' needs tree-sitter CLI and a C compiler. Run :checkhealth czernous, then :TSInstall ' .. lang .. '.')
    return false
  end
  pending[lang] = true
  vim.notify('Installing pinned syntax parser and queries for ' .. lang .. '...', vim.log.levels.INFO)
  nts.install(lang):await(function()
    pending[lang] = nil
    vim.schedule(function()
      managed[lang] = vim.tbl_contains(nts.get_installed(), lang)
      if managed[lang] then start(buf) end
    end)
  end)
  return true
end

function M.setup()
  local nts = require('nvim-treesitter')
  -- Match parsers and queries from the same managed bundle before legacy paths.
  nts.setup({ install_dir = vim.fn.stdpath('data') .. '/site' })
  local installed = nts.get_installed()
  for _, lang in ipairs(installed) do managed[lang] = true end
  local missing = vim.tbl_filter(function(l) return not vim.tbl_contains(installed, l) end, M.parsers)
  if #missing > 0 and cli() then nts.install(missing) end

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('czernous_treesitter', { clear = true }),
    callback = function(ev)
      local lang = vim.treesitter.language.get_lang(ev.match)
      if not lang then return end
      if managed[lang] then start(ev.buf); return end
      if vim.bo[ev.buf].buftype ~= '' then return end
      -- A legacy parser alone does not supply the plugin's current queries.
      if install_then_start(lang, ev.buf) then return end
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
