-- Formatting.
--
--   <leader>f  format now, instantly: the project's own formatter if there is
--              one (Biome, Prettier, StyLua, Ruff, Black... found on $PATH by
--              conform.nvim), otherwise the language server. For Java the
--              language server uses the project's Eclipse formatter file when the
--              build has one (the same formatter Spotless's eclipse() step runs),
--              so the result matches in practice; projects that format with
--              something else (google-java-format...) get a notice to use <leader>F.
--   <leader>F  exact Spotless, in Gradle projects that use it: byte-for-byte
--              what `./gradlew spotlessApply` produces (it also removes unused
--              imports etc.). Starts Gradle, so it takes about a second; runs in
--              the background and never overwrites edits made meanwhile.
--
-- Formatter programs are never installed from here: they come from the project
-- or the environment (devshell, toolchain), like language servers.

local M = {}

--------------------------------------------------------------------------------
-- <leader>f
--------------------------------------------------------------------------------

--- Formatter programs to try per filetype, in order: { conform's name, program }.
--- The first one found is used; none found -> the language server formats.
--- (conform.nvim is given this same table: see plugins/editor.lua.)
M.formatters = {
  lua = { { 'stylua', 'stylua' } },
  -- JS/TS: Biome, else oxfmt. No Prettier: slow, and superseded by these.
  javascript = { { 'biome', 'biome' }, { 'oxfmt', 'oxfmt' } },
  javascriptreact = { { 'biome', 'biome' }, { 'oxfmt', 'oxfmt' } },
  typescript = { { 'biome', 'biome' }, { 'oxfmt', 'oxfmt' } },
  typescriptreact = { { 'biome', 'biome' }, { 'oxfmt', 'oxfmt' } },
  json = { { 'biome', 'biome' } },
  jsonc = { { 'biome', 'biome' } },
  css = { { 'biome', 'biome' } },
  python = { { 'ruff_format', 'ruff' }, { 'black', 'black' } },
  nix = { { 'nixfmt', 'nixfmt' }, { 'alejandra', 'alejandra' } },
}

--- The table above in conform.nvim's `formatters_by_ft` shape.
function M.conform_by_ft()
  local out = {}
  for filetype, candidates in pairs(M.formatters) do
    out[filetype] = vim.tbl_map(function(c) return c[1] end, candidates)
    out[filetype].stop_after_first = true
  end
  return out
end

-- Where each formatter program is: $PATH value -> { program = absolute path | false }.
-- Programs are located ONCE per $PATH, by a background shell: asking Neovim
-- (`executable()`) on every key press costs ~100 ms per program that isn't there
-- when $PATH has slow entries. (A new $PATH, e.g. direnv entering a devshell,
-- is looked up afresh.)
local located = {}

--- Find `programs`; calls back with { program = path | false }, never blocking.
local function locate(programs, callback)
  local path = vim.env.PATH or ''
  located[path] = located[path] or {}
  local known, unknown = located[path], {}
  for _, program in ipairs(programs) do
    if known[program] == nil then unknown[#unknown + 1] = program end
  end
  if #unknown == 0 then return callback(known) end
  local script = 'for p in "$@"; do printf "%s=%s\\n" "$p" "$(command -v "$p" 2>/dev/null)"; done'
  vim.system(vim.list_extend({ 'sh', '-c', script, 'sh' }, unknown), { text = true }, function(r)
    for line in (r.stdout or ''):gmatch('[^\n]+') do
      local program, where = line:match('^([^=]+)=(.*)$')
      if program then known[program] = where ~= '' and where or false end
    end
    for _, program in ipairs(unknown) do
      if known[program] == nil then known[program] = false end
    end
    vim.schedule(function() callback(known) end)
  end)
end

--- A project's own copy (node_modules/.bin/<program>, looking upward from the file).
local function project_local(buf, program)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return nil end
  return vim.fs.find('node_modules/.bin/' .. program, { upward = true, path = vim.fs.dirname(name), limit = 1 })[1]
end

local function via_language_server(buf)
  -- Asked through Neovim, which also knows about servers that announce
  -- formatting only after they start (jdtls does).
  if #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' }) > 0 then
    vim.lsp.buf.format({ bufnr = buf, async = true })
    return
  end
  local filetype = vim.bo[buf].filetype
  local lsp = require('czernous.lsp')
  if lsp.is_starting and lsp.is_starting(buf) then
    vim.notify(('The language server for %s files is still starting; try again in a moment.'):format(filetype), vim.log.levels.WARN)
    return
  end
  vim.notify(('Nothing can format %s files here: no formatter program on $PATH and no language server that formats.')
    :format(filetype ~= '' and filetype or 'these'), vim.log.levels.WARN)
end

function M.format()
  local buf = vim.api.nvim_get_current_buf()
  local candidates = M.formatters[vim.bo[buf].filetype]
  if not candidates then return via_language_server(buf) end
  locate(vim.tbl_map(function(c) return c[2] end, candidates), function(where)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    for _, candidate in ipairs(candidates) do
      local name, program = candidate[1], candidate[2]
      local path = project_local(buf, program) or where[program]
      if path then
        local conform = require('conform')
        -- hand conform the exact program, so it has nothing to search for
        conform.formatters[name] = vim.tbl_extend('force', conform.formatters[name] or {}, { command = path })
        conform.format({ bufnr = buf, formatters = { name }, async = true, lsp_format = 'never' }, function(err)
          if err then vim.notify('Formatting failed: ' .. tostring(err), vim.log.levels.WARN) end
        end)
        return
      end
    end
    via_language_server(buf)
  end)
end

--------------------------------------------------------------------------------
-- Gradle + Spotless
--------------------------------------------------------------------------------
local function read(path)
  if vim.fn.filereadable(path) ~= 1 then return nil end
  return table.concat(vim.fn.readfile(path), '\n')
end

--- Gradle build files of a project: the root one, each module's, and shared
--- build logic (buildSrc / build-logic convention plugins).
local function build_files(root)
  local files = {}
  for _, pattern in ipairs({
    'build.gradle.kts', 'build.gradle', '*/build.gradle.kts', '*/build.gradle',
    'buildSrc/**/*.kts', 'buildSrc/**/*.gradle', 'buildSrc/**/*.kt',
    'build-logic/**/*.kts', 'build-logic/**/*.gradle', 'build-logic/**/*.kt',
  }) do
    vim.list_extend(files, vim.fn.globpath(root, pattern, false, true))
  end
  return files
end

-- root -> boolean. Build files are read once per project per session; restart
-- Neovim after adding Spotless to a build.
local uses_spotless = {}

local function detect_spotless(root)
  for _, path in ipairs(build_files(root)) do
    local text = read(path)
    if text and text:find('spotless', 1, true) then return true end
  end
  return false
end

--- The Eclipse formatter file a Gradle project formats Java with, if it has one:
--- the file its build passes to Spotless (`eclipse().configFile(...)`), else one
--- at a conventional path. Returns an absolute path or nil.
function M.eclipse_profile(root)
  for _, path in ipairs(build_files(root)) do
    local text = read(path)
    if text and text:find('configFile', 1, true) then
      for relative in text:gmatch('configFile%s*%(.-["\']([^"\']+%.xml)["\']') do
        -- paths in a build file are relative to the root project or to that file's folder
        for _, base in ipairs({ root, vim.fs.dirname(path) }) do
          local candidate = vim.fs.normalize(base .. '/' .. relative)
          if vim.fn.filereadable(candidate) == 1 then return candidate end
        end
      end
    end
  end
  for _, relative in ipairs({ 'config/eclipse-formatter.xml', 'eclipse-formatter.xml', 'config/formatter.xml', '.settings/formatter.xml' }) do
    local candidate = root .. '/' .. relative
    if vim.fn.filereadable(candidate) == 1 then return candidate end
  end
  return nil
end

--- Root of the Spotless-enabled Gradle project containing `buf`, or nil + why not.
local function spotless_root(buf)
  if vim.bo[buf].buftype ~= '' or vim.api.nvim_buf_get_name(buf) == '' then
    return nil, 'this buffer is not a file'
  end
  local root = vim.fs.root(buf, { 'gradlew' })
  if not root then return nil, 'this file is not in a Gradle project (no gradlew found)' end
  if uses_spotless[root] == nil then uses_spotless[root] = detect_spotless(root) end
  if not uses_spotless[root] then return nil, 'this Gradle project does not use Spotless' end
  if not vim.uv.fs_access(root .. '/gradlew', 'X') then
    return nil, root .. '/gradlew is not executable (chmod +x gradlew)'
  end
  return root
end

--- Does the Gradle project at `root` use Spotless? (cached per project)
function M.uses_spotless(root)
  if uses_spotless[root] == nil then uses_spotless[root] = detect_spotless(root) end
  return uses_spotless[root]
end

--- <leader>F: run the Spotless IDE hook on the buffer (stdin -> stdout; its
--- stderr says IS DIRTY / IS CLEAN).
function M.spotless()
  local buf = vim.api.nvim_get_current_buf()
  local root, why = spotless_root(buf)
  if not root then
    vim.notify('Spotless: ' .. why .. '. Use <leader>f to format.', vim.log.levels.WARN)
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  vim.system({
    root .. '/gradlew', '-q', 'spotlessApply',
    '-PspotlessIdeHook=' .. file, '-PspotlessIdeHookUseStdIn', '-PspotlessIdeHookUseStdOut',
  }, { cwd = root, stdin = input, text = true }, function(r)
    vim.schedule(function()
      local stderr = r.stderr or ''
      local status = stderr:match('IS DIRTY') or stderr:match('IS CLEAN')
      if r.code ~= 0 then
        vim.notify('Spotless failed:\n' .. vim.trim(stderr):sub(1, 400), vim.log.levels.WARN)
      elseif not status then
        vim.notify('Spotless does not cover this file (it is not in any Spotless target). Use <leader>f.', vim.log.levels.WARN)
      elseif status == 'IS CLEAN' or not vim.api.nvim_buf_is_valid(buf) then
        return
      elseif vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        vim.notify('Buffer changed while Spotless was running; run <leader>F again', vim.log.levels.WARN)
      elseif vim.trim(r.stdout or '') == '' then
        vim.notify('Spotless reported changes but returned no text; buffer left as is', vim.log.levels.WARN)
      else
        local lines = vim.split((r.stdout:gsub('\n$', '')), '\n', { plain = true })
        local view = vim.api.nvim_buf_call(buf, vim.fn.winsaveview)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_call(buf, function() vim.fn.winrestview(view) end)
      end
    end)
  end)
end

return M
