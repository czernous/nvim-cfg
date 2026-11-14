-- Finding programs on $PATH without ever making the editor wait.
--
-- Asking Neovim (`executable()`) costs ~100 ms per program that isn't there when
-- $PATH has slow entries (network or Windows mounts), so programs are located
-- ONCE per $PATH value, by a background shell, and remembered. A new $PATH
-- (e.g. direnv entering a devshell) is looked up afresh.

local M = {}

-- $PATH value -> { program = absolute path | false }
local located = {}

--- Find `programs`; calls back with { program = path | false }, never blocking.
function M.locate(programs, callback)
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

return M
