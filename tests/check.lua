-- Headless health check for this config. Run via ./tests/check.sh
-- Loaded with --cmd (before init.lua) so it can record every keymap the
-- config creates. Prints PASS/FAIL/SKIP lines; exit code = number of FAILs.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixtures = root .. '/tests/fixtures'

local check = { globals = {}, langs = {}, recorded = {}, errors = {}, results = {} }

---------------------------------------------------------------------------
-- Recording: keymaps and errors
---------------------------------------------------------------------------
local function classify(src)
  if src:find(root .. '/tests/', 1, true) then return 'test' end
  if src:find(root .. '/', 1, true) then return 'user' end
  if src:find('lazy/core/handler/keys', 1, true) then return 'lazy' end
  if src:find('which%-key/triggers') then return 'whichkey-trigger' end
  return 'other'
end

local orig_set = vim.keymap.set
vim.keymap.set = function(mode, lhs, rhs, opts)
  local src = (debug.getinfo(2, 'S') or {}).source or '?'
  local kind = classify(src)
  for _, m in ipairs(type(mode) == 'table' and mode or { mode }) do
    table.insert(check.recorded, {
      mode = m, lhs = lhs, rhs = rhs, desc = opts and opts.desc,
      buffer = opts and opts.buffer, src = src:gsub('^@', ''), kind = kind,
    })
  end
  return orig_set(mode, lhs, rhs, opts)
end

local orig_notify = vim.notify
vim.notify = function(msg, level, o)
  if level and level >= vim.log.levels.ERROR then
    table.insert(check.errors, tostring(msg))
  end
  return orig_notify(msg, level, o)
end

--- Keymaps created by the config itself (directly or via lazy.nvim `keys`).
function check.user_maps()
  return vim.tbl_filter(function(r) return r.kind == 'user' or r.kind == 'lazy' end, check.recorded)
end

---------------------------------------------------------------------------
-- Registration API (later tasks add checks here)
---------------------------------------------------------------------------
---@param name string
---@param fn fun(): boolean, string?
function check.global(name, fn) table.insert(check.globals, { name = name, fn = fn }) end

---@param spec {name:string, file:string, server:string, exe:string, timeout_ms?:integer}
function check.lang(spec) table.insert(check.langs, spec) end

local function report(status, name, msg)
  table.insert(check.results, status)
  io.stdout:write(('%s %s%s\n'):format(status, name, msg and (': ' .. msg) or ''))
end

local function norm(lhs)
  return vim.fn.keytrans(vim.keycode((lhs:gsub('<[Ll]eader>', vim.g.mapleader or '\\'))))
end

---------------------------------------------------------------------------
-- Global checks
---------------------------------------------------------------------------
check.global('keymaps_have_desc', function()
  local bad = {}
  for _, r in ipairs(check.user_maps()) do
    if not r.desc or r.desc == '' then
      table.insert(bad, ('%s %s (%s)'):format(r.mode, r.lhs, vim.fn.fnamemodify(r.src, ':t')))
    end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('no_prefix_clashes', function()
  -- All live mappings except which-key's own trigger mappings.
  local triggers = {}
  for _, r in ipairs(check.recorded) do
    if r.kind == 'whichkey-trigger' then triggers[r.mode .. norm(r.lhs)] = true end
  end
  local live = {}
  for _, m in ipairs({ 'n', 'x', 'o', 'i', 's' }) do
    local maps = vim.list_extend(vim.api.nvim_get_keymap(m), vim.api.nvim_buf_get_keymap(0, m))
    for _, k in ipairs(maps) do
      local key = norm(k.lhs)
      if not triggers[m .. key] then live[#live + 1] = { mode = m, lhs = key } end
    end
  end
  local bad, seen = {}, {}
  for _, r in ipairs(check.user_maps()) do
    local modes = r.mode == 'v' and { 'x', 's' } or { r.mode }
    for _, m in ipairs(modes) do
      local mine = norm(r.lhs)
      for _, other in ipairs(live) do
        if other.mode == m and #other.lhs > #mine and other.lhs:sub(1, #mine) == mine then
          local id = m .. ' ' .. mine .. ' < ' .. other.lhs
          if not seen[id] then seen[id] = true; bad[#bad + 1] = id end
        end
      end
    end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('no_shadowing', function()
  local globals, bad = {}, {}
  for _, r in ipairs(check.user_maps()) do
    if not r.buffer then globals[r.mode .. norm(r.lhs)] = r.desc or '?' end
  end
  for _, r in ipairs(check.user_maps()) do
    local g = r.buffer and globals[r.mode .. norm(r.lhs)]
    if g then bad[#bad + 1] = ('%s %s: global "%s" vs buffer "%s"'):format(r.mode, r.lhs, g, r.desc or '?') end
  end
  return #bad == 0, table.concat(vim.fn.uniq(vim.fn.sort(bad)), ', ')
end)

---------------------------------------------------------------------------
-- Language checks
---------------------------------------------------------------------------
check.lang({ name = 'go', file = fixtures .. '/go/main.go', server = 'gopls', exe = 'gopls' })
check.lang({ name = 'rust', file = fixtures .. '/rust/src/main.rs', server = 'rust_analyzer', exe = 'rust-analyzer', timeout_ms = 60000 })
check.lang({ name = 'csharp', file = fixtures .. '/csharp/Program.cs', server = 'csharp_ls', exe = 'csharp-ls', timeout_ms = 60000 })
check.lang({ name = 'ts', file = fixtures .. '/ts/index.ts', server = 'vtsls', exe = 'vtsls' })
check.lang({ name = 'java', file = fixtures .. '/java/src/Main.java', server = 'jdtls', exe = 'jdtls', timeout_ms = 90000 })
check.lang({ name = 'lua', file = fixtures .. '/lua/init.lua', server = 'lua_ls', exe = 'lua-language-server' })
if vim.env.CHECK_JAVA_PROJECT and vim.env.CHECK_JAVA_PROJECT ~= '' then
  local f = vim.fn.globpath(vim.env.CHECK_JAVA_PROJECT, '**/src/main/**/*.java', false, true)[1]
  if f then check.lang({ name = 'java-project', file = f, server = 'jdtls', exe = 'jdtls', timeout_ms = 180000 }) end
end

--- Put the cursor on the last call of the fixture's `add`/`Add` function.
local function cursor_on_call(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = #lines, 1, -1 do
    local col = lines[i]:find('[aA]dd%(')
    if col then vim.api.nvim_win_set_cursor(0, { i, col - 1 }); return true end
  end
end

local function run_lang(spec)
  vim.cmd('silent! %bwipeout!')
  vim.cmd.edit(vim.fn.fnameescape(spec.file))
  local buf = vim.api.nvim_get_current_buf()
  local name = 'lang:' .. spec.name

  vim.wait(3000, function() return vim.treesitter.highlighter.active[buf] ~= nil end, 50)
  if not vim.treesitter.highlighter.active[buf] then
    return report('FAIL', name .. ':treesitter', 'no highlighter for ft=' .. vim.bo[buf].filetype)
  end
  report('PASS', name .. ':treesitter')

  if vim.fn.executable(spec.exe) ~= 1 then
    return report('SKIP', name .. ':lsp', spec.exe .. ' not on PATH')
  end
  local timeout = spec.timeout_ms or 20000
  local client
  vim.wait(timeout, function()
    client = vim.lsp.get_clients({ bufnr = buf, name = spec.server })[1]
    return client ~= nil and client.initialized
  end, 100)
  if not client then
    return report('FAIL', name .. ':lsp', spec.server .. ' did not attach within ' .. timeout .. 'ms')
  end
  report('PASS', name .. ':lsp')

  if spec.name == 'java-project' then return end -- real projects: attach is enough
  if not cursor_on_call(buf) then return report('FAIL', name .. ':definition', 'no add( call in fixture') end
  local found = false
  local deadline = vim.uv.now() + timeout
  while not found and vim.uv.now() < deadline do
    -- Some servers (jdtls) register capabilities after init; wait for them.
    if not client:supports_method('textDocument/definition', buf) then
      vim.wait(1000)
      goto continue
    end
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local res = vim.lsp.buf_request_sync(buf, 'textDocument/definition', params, 5000) or {}
    for _, r in pairs(res) do
      local loc = r.result
      if loc and (loc.uri or loc.targetUri or #loc > 0) then found = true end
    end
    if not found then vim.wait(1000) end
    ::continue::
  end
  report(found and 'PASS' or 'FAIL', name .. ':definition', not found and 'no definition location' or nil)
end

---------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------
local function run()
  vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy', modeline = false })
  vim.wait(500)

  for _, spec in ipairs(check.langs) do
    local ok, err = pcall(run_lang, spec)
    if not ok then report('FAIL', 'lang:' .. spec.name, err) end
  end

  for _, g in ipairs(check.globals) do
    local ok, passed, msg = pcall(g.fn)
    if not ok then report('FAIL', g.name, passed)
    elseif passed then report('PASS', g.name)
    else report('FAIL', g.name, msg) end
  end

  -- Errors last, so everything above had a chance to produce them.
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  for line in msgs:gmatch('[^\n]+') do
    if line:match('^E%d+:') or line:match('^Error') then table.insert(check.errors, line) end
  end
  report(#check.errors == 0 and 'PASS' or 'FAIL', 'no_error_messages', table.concat(check.errors, ' | '))

  local counts = { PASS = 0, FAIL = 0, SKIP = 0 }
  for _, s in ipairs(check.results) do counts[s] = counts[s] + 1 end
  io.stdout:write(('\n%d passed, %d failed, %d skipped\n'):format(counts.PASS, counts.FAIL, counts.SKIP))
  vim.cmd('cquit ' .. math.min(counts.FAIL, 255))
end

_G.CzCheck = check
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function() vim.defer_fn(function()
    local ok, err = pcall(run)
    if not ok then io.stdout:write('FAIL runner: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
  end, 100) end,
})
