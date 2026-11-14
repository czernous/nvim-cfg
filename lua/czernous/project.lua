-- "Which project is this file in?" Used by the search keys (<leader>pf, pg, ps)
-- so they search the current file's project, not wherever Neovim was started.
--
-- Checked in order (first tier that matches anywhere above the file wins):
--   1. multi-module roots: Gradle settings/gradlew, go.work, Cargo.lock, *.sln
--   2. nearest single project: go.mod, Cargo.toml, package.json, *.csproj, ...
--   3. the git repository root
--   4. Neovim's working directory

local M = {}

local function any_of(names, patterns)
  local set = {}
  for _, n in ipairs(names) do set[n] = true end
  return function(name)
    if set[name] then return true end
    for _, p in ipairs(patterns or {}) do
      if name:match(p) then return true end
    end
    return false
  end
end

local tiers = {
  any_of({ 'settings.gradle', 'settings.gradle.kts', 'gradlew', 'go.work', 'Cargo.lock' }, { '%.sln$', '%.slnx$' }),
  any_of({ 'go.mod', 'Cargo.toml', 'package.json', 'deno.json', 'pom.xml', 'build.gradle', 'build.gradle.kts',
    'pyproject.toml', 'Makefile' }, { '%.csproj$', '%.fsproj$' }),
  any_of({ '.git' }),
}

--- Project root for `buf` (0 = current buffer).
---@param buf? integer
---@return string
function M.root(buf)
  buf = buf or 0
  if vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= '' then
    for _, marker in ipairs(tiers) do
      local found = vim.fs.root(buf, marker)
      if found then return found end
    end
  end
  return vim.fn.getcwd()
end

return M
