-- :checkhealth czernous
--
-- Lists the programs this config expects to find on $PATH and says what stops
-- working without each one. Nothing is installed from here: tools come from the
-- language's own toolchain, a devshell, or your system's packages -- this page
-- is how you see what a machine is missing.
--
-- (Runs only when you ask for it, so looking programs up one by one is fine here.)

local M = {}

local function found(program) return vim.fn.executable(program) == 1 end

--- First program of the list that exists, or nil.
local function first(programs)
  for _, program in ipairs(programs) do
    if found(program) then return program end
  end
end

function M.check()
  local health = vim.health
  -- Mason adds its folder to $PATH just after startup; make sure that has
  -- happened, or servers installed through Mason would be reported missing.
  vim.api.nvim_exec_autocmds('User', { pattern = 'CzernousLspSetup', modeline = false })

  health.start('czernous: needed for the basics')
  local basics = {
    { { 'git' }, 'git', 'installing plugins; git change markers; :Git' },
    { { 'cc', 'gcc', 'clang' }, 'a C compiler (gcc or clang)', 'building syntax-highlighting parsers' },
    { { 'tree-sitter' }, 'the tree-sitter command-line tool', 'building syntax-highlighting parsers (highlighting for new languages)' },
    { { 'rg' }, 'ripgrep (rg)', 'searching inside files (<leader>pg, <leader>ps, <leader>pw)' },
    { { 'fd', 'fdfind' }, 'fd', 'fast file finding (<leader>pf falls back to a slower search without it)' },
  }
  for _, tool in ipairs(basics) do
    local program = first(tool[1])
    if program then
      health.ok(('%s: %s'):format(tool[2], vim.fn.exepath(program)))
    else
      health.error(('%s not found on $PATH'):format(tool[2]), { 'Needed for: ' .. tool[3], 'Install it with your system package manager or devshell.' })
    end
  end

  health.start('czernous: language servers (code intelligence)')
  local servers = require('czernous.lsp').servers
  local names = vim.tbl_keys(servers)
  table.sort(names)
  for _, name in ipairs(names) do
    local program = servers[name]
    if found(program) then
      health.ok(('%s: %s'):format(program, vim.fn.exepath(program)))
    else
      health.warn(('%s not found on $PATH'):format(program), {
        ('Without it there is no completion, documentation (K) or go-to-definition for that language (server: %s).'):format(name),
        'Get it from the language toolchain or devshell; :MasonInstall is a fallback.',
      })
    end
  end

  health.start('czernous: formatters (<leader>f)')
  health.info('<leader>f uses a formatter program if one is on $PATH, otherwise the language server. :ConformInfo shows what would run for the current file.')
  for _, program in ipairs({ 'stylua', 'biome', 'oxfmt', 'ruff', 'black', 'nixfmt', 'leptosfmt' }) do
    if found(program) then
      health.ok(('%s: %s'):format(program, vim.fn.exepath(program)))
    else
      health.info(program .. ': not on $PATH (only needed if a project formats with it)')
    end
  end

  health.start('czernous: debuggers (<leader>b)')
  for _, debugger in ipairs(require('czernous.debugging').debuggers) do
    local program = first(debugger.programs)
    local languages = table.concat(debugger.filetypes, ', ')
    if program then
      health.ok(('%s (%s): %s'):format(program, languages, vim.fn.exepath(program)))
    else
      health.info(('%s: not on $PATH (%s; only needed to debug %s)'):format(table.concat(debugger.programs, ' / '), debugger.what, languages))
    end
  end

  health.start('czernous: clipboard')
  if vim.fn.has('clipboard') == 1 then
    health.ok('a clipboard tool was found: <leader>y copies to the system clipboard')
  else
    health.warn('no clipboard tool found', {
      '<leader>y / <leader>Y cannot reach the system clipboard.',
      'Install one for your system: wl-clipboard (Wayland), xclip (X11), win32yank.exe (WSL); macOS has pbcopy built in.',
    })
  end
end

return M
