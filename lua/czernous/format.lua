-- Formatting for <leader>f. The project's own formatter wins:
--   1. Spotless -- if the file is in a Gradle project (nearest ./gradlew) whose
--      build uses Spotless: identical to `./gradlew spotlessApply` (~1s, async).
--   2. LSP      -- the language server's formatter (gopls, rust-analyzer via
--      rustfmt.toml, csharp-ls via .editorconfig, jdtls, ...).
--   3. Neoformat -- external CLI formatters (prettier, biome, ...) if installed.

local M = {}

local function mentions_spotless(path)
  if vim.fn.filereadable(path) ~= 1 then return false end
  return table.concat(vim.fn.readfile(path), '\n'):find('spotless', 1, true) ~= nil
end

-- root -> boolean. Reading build files once per project per session is enough;
-- restart Neovim after adding Spotless to a build.
local uses_spotless = {}

--- Does the Gradle build at `root` use Spotless? Looks where builds commonly
--- declare it: the root build file, each module's build file, and shared build
--- logic (buildSrc / build-logic convention plugins).
local function detect_spotless(root)
  for _, name in ipairs({ 'build.gradle.kts', 'build.gradle' }) do
    if mentions_spotless(root .. '/' .. name) then return true end
  end
  for _, pattern in ipairs({
    '*/build.gradle.kts', '*/build.gradle',
    'buildSrc/**/*.kts', 'buildSrc/**/*.gradle', 'buildSrc/**/*.kt',
    'build-logic/**/*.kts', 'build-logic/**/*.gradle', 'build-logic/**/*.kt',
  }) do
    for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
      if mentions_spotless(path) then return true end
    end
  end
  return false
end

--- Root of a Spotless-enabled Gradle project containing `buf`, or nil.
local function spotless_root(buf)
  -- Only real files (not [No Name], :help, terminals...).
  if vim.bo[buf].buftype ~= '' or vim.api.nvim_buf_get_name(buf) == '' then return nil end
  local root = vim.fs.root(buf, { 'gradlew' })
  if not root then return nil end
  if uses_spotless[root] == nil then uses_spotless[root] = detect_spotless(root) end
  if not uses_spotless[root] then return nil end
  if not vim.uv.fs_access(root .. '/gradlew', 'X') then
    vim.notify(root .. '/gradlew is not executable (chmod +x gradlew); formatting without Spotless', vim.log.levels.WARN)
    return nil
  end
  return root
end

local function fallback(buf)
  if #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' }) > 0 then
    vim.lsp.buf.format({ bufnr = buf })
  else
    vim.cmd('Neoformat')
  end
end

--- Spotless IDE hook: stdin -> stdout; stderr says IS DIRTY / IS CLEAN.
local function spotless(buf, root)
  local file = vim.api.nvim_buf_get_name(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  vim.system({
    root .. '/gradlew', '-q', 'spotlessApply',
    '-PspotlessIdeHook=' .. file, '-PspotlessIdeHookUseStdIn', '-PspotlessIdeHookUseStdOut',
  }, { cwd = root, stdin = input, text = true }, function(r)
    vim.schedule(function()
      local status = (r.stderr or ''):match('IS DIRTY') or (r.stderr or ''):match('IS CLEAN')
      if r.code == 0 and not status then
        -- File isn't covered by any Spotless target (e.g. .yml, .md): use the LSP.
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_call(buf, function() fallback(buf) end) end
        return
      end
      if r.code ~= 0 or not status then
        vim.notify('Spotless failed:\n' .. vim.trim(r.stderr or ''):sub(1, 400), vim.log.levels.WARN)
        return
      end
      if status == 'IS CLEAN' or not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        vim.notify('Buffer changed while formatting; run <leader>f again', vim.log.levels.WARN)
        return
      end
      if vim.trim(r.stdout or '') == '' then
        vim.notify('Spotless reported changes but returned no text; buffer left as is', vim.log.levels.WARN)
        return
      end
      local lines = vim.split((r.stdout:gsub('\n$', '')), '\n', { plain = true })
      local view = vim.api.nvim_buf_call(buf, vim.fn.winsaveview)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_call(buf, function() vim.fn.winrestview(view) end)
    end)
  end)
end

function M.format()
  local buf = vim.api.nvim_get_current_buf()
  local root = spotless_root(buf)
  if root then spotless(buf, root) else fallback(buf) end
end

return M
