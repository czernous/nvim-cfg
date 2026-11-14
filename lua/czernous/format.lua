-- Formatting.
--
--   <leader>f  format now, instantly: the project's own formatter if there is
--              one (Biome, Prettier, StyLua, Ruff, Black... found on $PATH by
--              conform.nvim), otherwise the language server. For Java the
--              language server uses the project's Eclipse formatter file -- the
--              same formatter Spotless runs -- so the result matches in practice.
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
function M.format()
  local buf = vim.api.nvim_get_current_buf()
  local conform = require('conform')
  -- 1. a formatter program for this filetype that is actually on $PATH
  if #conform.list_formatters_to_run(buf) > 0 then
    conform.format({ bufnr = buf, async = true, lsp_format = 'never' }, function(err)
      if err then vim.notify('Formatting failed: ' .. tostring(err), vim.log.levels.WARN) end
    end)
    return
  end
  -- 2. the language server. Asked through Neovim, which also knows about
  --    servers that announce formatting only after they start (jdtls does).
  if #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' }) > 0 then
    vim.lsp.buf.format({ bufnr = buf, async = true })
    return
  end
  local filetype = vim.bo[buf].filetype
  vim.notify(('Nothing can format %s files here: no formatter program on $PATH and no language server that formats.')
    :format(filetype ~= '' and filetype or 'these'), vim.log.levels.WARN)
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
