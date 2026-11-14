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
  if src:find(root .. '/tests/tripwires/', 1, true) then return 'user' end -- deliberate violations
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

check.startup_lookups = {}
check.exe_calls = {}
check.blocking = {}      -- blocking calls made by config code: { name, src, phase }
check.global_writes = {} -- globals created by config code: { name, src }
check.hot = false        -- true while the check fires hot-path events

--- First stack frame that is config code (lua/, after/, or a tripwire), if any.
local function config_caller()
  for level = 3, 12 do
    local info = debug.getinfo(level, 'Sl')
    if not info then return nil end
    local src = info.source:gsub('^@', '')
    if classify(src) == 'user' then return src:sub(#root + 2) .. ':' .. (info.currentline or 0) end
  end
end

local function record_blocking(name)
  local phase = (vim.v.vim_did_enter == 0 and 'startup') or (check.hot and 'hot path') or 'after startup'
  local src = config_caller()
  if src then table.insert(check.blocking, { name = name, src = src, phase = phase }) end
end

local orig_executable = vim.fn.executable
vim.fn.executable = function(name)
  if vim.v.vim_did_enter == 0 then table.insert(check.startup_lookups, name) end
  check.exe_calls[name] = (check.exe_calls[name] or 0) + 1
  record_blocking('vim.fn.executable(' .. tostring(name) .. ')')
  return orig_executable(name)
end
for _, fname in ipairs({ 'system', 'systemlist', 'exepath' }) do
  local orig = vim.fn[fname]
  vim.fn[fname] = function(...) record_blocking('vim.fn.' .. fname); return orig(...) end
end
do
  local popen, execute, system = io.popen, os.execute, vim.system
  io.popen = function(...) record_blocking('io.popen'); return popen(...) end
  os.execute = function(...) record_blocking('os.execute'); return execute(...) end
  vim.system = function(cmd, opts, on_exit)
    local obj = system(cmd, opts, on_exit)
    local wait = obj.wait
    obj.wait = function(self, ...) record_blocking('vim.system():wait()'); return wait(self, ...) end
    return obj
  end
end

setmetatable(_G, {
  __newindex = function(t, k, v)
    rawset(t, k, v)
    local info = debug.getinfo(2, 'Sl')
    local src = info and info.source:gsub('^@', '') or ''
    if classify(src) == 'user' then
      table.insert(check.global_writes, { name = tostring(k), src = src:sub(#root + 2) .. ':' .. (info.currentline or 0) })
    end
  end,
})

-- Tripwires: CHECK_TRIPWIRE=<name> loads a deliberate violation as if it were
-- config code, to prove the matching check can fail (see check.sh --tripwires).
check.tripwire = vim.env.CHECK_TRIPWIRE
if check.tripwire and check.tripwire ~= '' then
  vim.opt.runtimepath:prepend(root .. '/tests/tripwires')
  require('czernous.tripwire_' .. check.tripwire)
end

local orig_notify = vim.notify
vim.notify = function(msg, level, o)
  if level and level >= vim.log.levels.ERROR then
    table.insert(check.errors, tostring(msg))
  end
  return orig_notify(msg, level, o)
end

--- Copy error lines from :messages into check.errors (call before any `messages clear`).
--- Errors raised in vim.schedule callbacks only ever reach :messages.
function check.snapshot_messages()
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  for line in msgs:gmatch('[^\n]+') do
    if line:match('^E%d+:') or line:match('^Error') or line:find('callback: ', 1, true)
      or line:find('stack traceback', 1, true) or line:find('install/[%w_]+ error') then
      table.insert(check.errors, line)
    end
  end
end

-- CHECK_CANARY=1 injects a scheduled error at startup to prove it gets caught.
if vim.env.CHECK_CANARY == '1' then vim.schedule(function() error('canary error') end) end

--- Keymaps created by the config itself (directly or via lazy.nvim `keys`).
function check.user_maps()
  return vim.tbl_filter(function(r) return r.kind == 'user' or r.kind == 'lazy' end, check.recorded)
end

---------------------------------------------------------------------------
-- Registration API (later tasks add checks here)
---------------------------------------------------------------------------
---@param name string
---@param fn fun(): boolean, string?
---@param opts? { early?: boolean, late?: boolean }
---   early = run before the language checks, while the machine is still quiet
---           (timing checks: language servers started later skew them)
---   late  = run after every other check (checks that judge what the whole run did)
function check.global(name, fn, opts)
  table.insert(check.globals, { name = name, fn = fn, early = opts and opts.early or false, late = opts and opts.late or false })
end

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
        -- ...and the other way round: a live mapping that makes one of ours wait.
        if other.mode == m and #other.lhs < #mine and mine:sub(1, #other.lhs) == other.lhs then
          local id = m .. ' ' .. other.lhs .. ' < ' .. mine
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

-- Every key the config defines must come from the single registry file
-- (directly, or via lazy.nvim `keys` generated from it).
check.global('keymaps_central', function()
  local ok_reg, reg = pcall(require, 'czernous.keymaps')
  local registered = {}
  if ok_reg and type(reg) == 'table' and reg.all then
    for _, k in ipairs(reg.all()) do registered[k.mode .. norm(k.lhs)] = true end
  end
  local bad = {}
  for _, r in ipairs(check.user_maps()) do
    local ok
    if r.kind == 'lazy' then ok = registered[r.mode .. norm(r.lhs)]
    else ok = r.src:match('lua/czernous/keymaps%.lua$') ~= nil end
    if not ok then bad[#bad + 1] = ('%s %s (%s)'):format(r.mode, r.lhs, vim.fn.fnamemodify(r.src, ':t')) end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

-- Fails on the same mode+lhs defined twice in the registry; otherwise prints
-- (as INFO) keys that do the same thing, for the owner to pick from.
check.global('duplicate_actions_report', function()
  local ok_reg, reg = pcall(require, 'czernous.keymaps')
  if not (ok_reg and type(reg) == 'table' and reg.groups) then return false, 'no registry' end
  local by_lhs, by_rhs, dup = {}, {}, {}
  for _, g in ipairs(reg.groups) do
    for _, k in ipairs(g.keys) do
      for _, m in ipairs(type(k[1]) == 'table' and k[1] or { k[1] }) do
        local id = (g.buffer or 'global') .. ' ' .. m .. ' ' .. norm(k[2])
        if by_lhs[id] then dup[#dup + 1] = id end
        by_lhs[id] = true
        local rkey = type(k[3]) == 'string' and (m .. ':' .. k[3]) or k[3]
        by_rhs[rkey] = by_rhs[rkey] or {}
        local list = by_rhs[rkey]
        local seen_lhs = false
        for _, e in ipairs(list) do if e.lhs == k[2] then seen_lhs = true end end
        if not seen_lhs then list[#list + 1] = { lhs = k[2], text = ('%s %s (%s)'):format(m, k[2], k.desc or '?') } end
      end
    end
  end
  for _, keys in pairs(by_rhs) do
    if #keys > 1 then
      io.stdout:write('INFO same action: ' .. table.concat(vim.tbl_map(function(e) return e.text end, keys), '  =  ') .. '\n')
    end
  end
  return #dup == 0, 'defined twice: ' .. table.concat(dup, ', ')
end)

-- <C-space> selects the node under the cursor; pressing it again (in visual
-- mode) must stay in visual mode and select a larger node.
check.global('incremental_selection_grows', function()
  vim.cmd('silent! %bwipeout!')
  vim.cmd.edit(fixtures .. '/lua/init.lua')
  vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- on `a` in `return a + b`
  local function sel()
    local s, e = vim.fn.getpos('v'), vim.fn.getpos('.')
    return math.abs((e[2] - s[2]) * 1000 + e[3] - s[3])
  end
  vim.api.nvim_feedkeys(vim.keycode('<C-space>'), 'x', false)
  local mode1, size1 = vim.fn.mode(), sel()
  vim.api.nvim_feedkeys(vim.keycode('<C-space>'), 'x', false)
  local mode2, size2 = vim.fn.mode(), sel()
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'x', false)
  local ok = mode1 == 'v' and mode2 == 'v' and size2 > size1
  local n = vim.treesitter.get_node()
  return ok, ('after 1st: mode=%s size=%d; after 2nd: mode=%s size=%d; node=%s ft=%s map=%s'):format(mode1, size1, mode2, size2, n and n:type(), vim.bo.filetype, vim.fn.maparg('<C-Space>', 'n') ~= '')
end)

-- LSP: servers come from $PATH; Mason is only a fallback.
check.global('mason_is_fallback_only', function()
  if package.loaded['mason-lspconfig'] then return false, 'mason-lspconfig is loaded' end
  local parts = vim.split(vim.env.PATH, ':', { plain = true })
  local mason_bin = vim.fn.stdpath('data') .. '/mason/bin'
  local idx
  for i, p in ipairs(parts) do if p == mason_bin then idx = i end end
  if not idx then return false, 'mason bin not on PATH' end
  return idx == #parts, ('mason bin at PATH position %d of %d (want last)'):format(idx, #parts)
end)

-- Startup must not search $PATH for servers: each miss can cost ~100ms when
-- $PATH has slow entries (network/Windows mounts). Lookups run in the background.
check.global('no_startup_path_lookups', function()
  local servers = {}
  for _, exe in pairs(require('czernous.lsp').servers) do servers[exe] = true end
  local bad = vim.tbl_filter(function(n) return servers[n] end, check.startup_lookups)
  return #bad == 0, 'looked up during startup: ' .. table.concat(bad, ', ')
end)

-- `nvim file.lua` (file opened before startup finishes) must still get LSP.
check.global('direct_open_attaches', function()
  if vim.fn.executable('lua-language-server') == 0 then return 'skip', 'lua-language-server not on PATH' end
  local probe = vim.fn.tempname() .. '.lua'
  vim.fn.writefile({
    "vim.api.nvim_create_autocmd('VimEnter', { callback = function() vim.defer_fn(function()",
    "  vim.wait(20000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end, 100)",
    "  io.stdout:write('ATTACHED=' .. #vim.lsp.get_clients({ bufnr = 0 }) .. '\\n'); vim.cmd('qa!')",
    "end, 10) end })",
  }, probe)
  -- Minimal PATH so the background lookup finishes BEFORE startup does (the race).
  local nvim_dir = vim.fn.fnamemodify(vim.v.progpath, ':h')
  local env = { PATH = nvim_dir .. ':/usr/bin:/bin' }
  -- `-c vim.wait` = something processing events during startup (e.g. a plugin waiting).
  local r = vim.system({ vim.v.progpath, '--headless', '--cmd', 'luafile ' .. probe, '-c', 'lua vim.wait(2000)', fixtures .. '/lua/init.lua' },
    { text = true, env = env }):wait(40000)
  return (r.stdout or ''):find('ATTACHED=[1-9]') ~= nil, 'child output: ' .. vim.trim((r.stdout or '') .. (r.stderr or ''))
end)

check.global('enabled_matches_path', function()
  local ok, lsp = pcall(require, 'czernous.lsp')
  if not ok or type(lsp) ~= 'table' or not lsp.servers or not lsp.enabled then return false, 'czernous.lsp has no servers/enabled' end
  local want, got = {}, {}
  for name, exe in pairs(lsp.servers) do
    if vim.fn.executable(exe) == 1 then want[#want + 1] = name end
  end
  vim.wait(10000, function() return lsp.ready end, 50)
  for _, name in ipairs(lsp.enabled) do got[#got + 1] = name end
  table.sort(want); table.sort(got)
  return vim.deep_equal(want, got), ('want %s got %s'):format(vim.inspect(want), vim.inspect(got))
end)

check.global('leptosfmt_conditional', function()
  local cfg = vim.lsp.config.rust_analyzer or {}
  local ra = vim.tbl_get(cfg, 'settings', 'rust-analyzer') or {}
  if not vim.tbl_get(ra, 'procMacro', 'ignored', 'leptos_macro') then return false, 'leptos procMacro settings missing' end
  local has = vim.fn.executable('leptosfmt') == 1
  local override = vim.tbl_get(ra, 'rustfmt', 'overrideCommand')
  return (override ~= nil) == has, ('leptosfmt on PATH=%s, override set=%s'):format(has, override ~= nil)
end)

check.global('jdtls_no_hardcoded_runtime', function()
  local hits = vim.fn.systemlist({ 'grep', '-rlE', '/usr/lib/jvm|\\.sdkman|jdk-?[0-9]', root .. '/lua', root .. '/after' })
  hits = vim.tbl_filter(function(h) return h ~= '' and not h:find('No such file') end, hits)
  if #hits > 0 then return false, 'hardcoded JDK path in ' .. table.concat(hits, ', ') end
  local runtimes = vim.tbl_get(vim.lsp.config.jdtls or {}, 'settings', 'java', 'configuration', 'runtimes')
  if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= '' then
    return runtimes and runtimes[1].path == vim.env.JAVA_HOME, 'JAVA_HOME set but not used as runtime'
  end
  local cmd = (vim.lsp.config.jdtls or {}).cmd
  return runtimes == nil and type(cmd) == 'function', 'runtimes set without JAVA_HOME, or cmd not overridden'
end)

-- A server binary that exists but crashes must not produce ERROR messages.
check.global('broken_server_is_quiet', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ '#!/bin/sh', 'exit 1' }, dir .. '/fake-ls'); vim.fn.setfperm(dir .. '/fake-ls', 'rwxr-xr-x')
  local old = vim.env.PATH; vim.env.PATH = dir .. ':' .. old
  local before = #check.errors
  local warns = 0
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warns = warns + 1 end return n(m, l, o) end
  vim.lsp.config('fake_ls', { cmd = { 'fake-ls' }, filetypes = { 'czfake' } })
  vim.lsp.enable('fake_ls')
  -- Several buffers: a dead server must not be restarted (and warn) for each one.
  vim.cmd('silent! %bwipeout!')
  for i = 1, 3 do
    vim.cmd.edit(dir .. '/x' .. i .. '.czfake'); vim.bo.filetype = 'czfake'
    vim.wait(1500)
  end
  vim.lsp.enable('fake_ls', false)
  vim.notify = n; vim.env.PATH = old
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  local errs = #check.errors - before
  for line in msgs:gmatch('[^\n]+') do if line:match('^E%d+:') or line:match('^Error') then errs = errs + 1 end end
  check.snapshot_messages()
  vim.cmd('messages clear')
  return errs == 0 and warns <= 1, ('errors=%d warns=%d'):format(errs, warns)
end)

check.global('rootless_file_is_quiet', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'package main', '', 'func main() {}' }, dir .. '/x.go')
  local before = #check.errors
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/x.go')
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(5000)
  if not vim.treesitter.highlighter.active[buf] then return false, 'no highlighting for a lone .go file' end
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  local bad = #check.errors - before
  for line in msgs:gmatch('[^\n]+') do if line:match('^E%d+:') or line:match('^Error') then bad = bad + 1 end end
  return bad == 0, msgs
end)

-- Treesitter: owner's languages are kept installed; others install on first open.
check.global('parsers_installed', function()
  local ok, tsm = pcall(require, 'czernous.treesitter')
  if not ok or not tsm.parsers then return false, 'czernous.treesitter has no parsers list' end
  local need = { 'go', 'gomod', 'rust', 'c_sharp', 'java', 'javascript', 'typescript', 'tsx', 'lua' }
  local missing = {}
  local installed = require('nvim-treesitter').get_installed()
  for _, l in ipairs(need) do
    if not vim.tbl_contains(tsm.parsers, l) then missing[#missing + 1] = l .. ' (not in list)'
    elseif not vim.tbl_contains(installed, l) then missing[#missing + 1] = l .. ' (not installed)' end
  end
  return #missing == 0, table.concat(missing, ', ')
end)

-- Opens a buffer with an available-but-uninstalled language; returns install calls.
local function install_calls_on_open(path_override)
  local nts = require('nvim-treesitter')
  local available = nts.get_available()
  local installed = nts.get_installed()
  local lang
  for _, l in ipairs({ 'zig', 'elixir', 'ocaml', 'haskell', 'erlang' }) do
    if vim.tbl_contains(available, l) and not vim.tbl_contains(installed, l) then lang = l; break end
  end
  if not lang then return nil, 'no uninstalled test language available' end
  local calls = {}
  local real = nts.install
  nts.install = function(langs)
    calls[#calls + 1] = langs
    return { await = function() end }
  end
  local old = vim.env.PATH
  if path_override then vim.env.PATH = path_override end
  vim.cmd('silent! %bwipeout!'); vim.cmd('enew')
  local ok, err = pcall(function() vim.bo.filetype = lang end)
  vim.env.PATH = old
  nts.install = real
  if not ok then return nil, err end
  return calls
end

check.global('auto_install_on_open', function()
  if vim.fn.executable('tree-sitter') == 0 then return true end
  local calls, err = install_calls_on_open()
  if not calls then return false, err end
  return #calls == 1, ('install called %d times'):format(#calls)
end)

check.global('no_cli_no_install', function()
  local before = #check.errors
  -- PATH without the tree-sitter CLI
  local dirs = vim.tbl_filter(function(d) return vim.fn.executable(d .. '/tree-sitter') == 0 end,
    vim.split(vim.env.PATH, ':', { plain = true }))
  local calls, err = install_calls_on_open(table.concat(dirs, ':'))
  if not calls then return false, err end
  return #calls == 0 and #check.errors == before, ('install called %d times, errors=%d'):format(#calls, #check.errors - before)
end)

-- Errors findable without virtual text (owner: virtual text hurts performance).
check.global('diagnostics_findable', function()
  local c = vim.diagnostic.config()
  if c.virtual_text then return false, 'virtual_text is on' end
  if not c.severity_sort then return false, 'severity_sort off' end
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  local ns = vim.api.nvim_create_namespace('czcheck')
  vim.diagnostic.set(ns, 0, { { lnum = 4, col = 0, message = 'injected', severity = vim.diagnostic.severity.ERROR } })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local before = #vim.api.nvim_list_wins()
  vim.api.nvim_feedkeys(']d', 'x', false)
  vim.wait(200)
  local opened = #vim.api.nvim_list_wins() > before
  local line = vim.api.nvim_win_get_cursor(0)[1]
  vim.diagnostic.reset(ns)
  return opened and line == 5, ('float opened=%s cursor line=%d'):format(opened, line)
end)

check.global('signcolumn_fixed', function()
  return vim.o.signcolumn == 'yes', 'signcolumn=' .. vim.o.signcolumn
end)

check.global('source_only_lua_vim', function()
  local key
  for _, k in ipairs(require('czernous.keymaps').all()) do if k.lhs == '<leader><leader>' then key = k end end
  if not key then return false, '<leader><leader> not found' end
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/go/main.go')
  local before = #check.errors
  local warned = false
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warned = true end return n(m, l, o) end
  local ok = pcall(vim.api.nvim_feedkeys, vim.keycode('<leader><leader>'), 'x', false)
  vim.notify = n
  return ok and warned and #check.errors == before, ('ok=%s warned=%s'):format(ok, warned)
end)

check.global('which_key_groups_used', function()
  local reg = require('czernous.keymaps')
  local bad = {}
  for _, p in ipairs(reg.prefixes or {}) do
    local used = false
    for _, g in ipairs(reg.groups) do
      for _, key in ipairs(g.keys) do
        for _, m in ipairs(type(key[1]) == 'table' and key[1] or { key[1] }) do
          local same_mode = (p.mode or 'n') == m or ((p.mode == 'v') and (m == 'x' or m == 'v'))
          if same_mode and key[2] ~= p[1] and key[2]:sub(1, #p[1]) == p[1] then used = true end
        end
      end
    end
    if not used then bad[#bad + 1] = ('%s "%s"'):format(p[1], p.group) end
  end
  if #(reg.prefixes or {}) == 0 then return false, 'keymaps.prefixes is empty (was it handed to which-key without copying?)' end
  return #bad == 0, 'which-key labels for prefixes that have no keys: ' .. table.concat(bad, ', ')
end)

-- Owner's choices at the Task 2 checkpoint.
check.global('owner_key_choices', function()
  local have = {}
  for _, k in ipairs(require('czernous.keymaps').all()) do have[k.mode .. ' ' .. k.lhs] = true end
  local bad = {}
  for _, gone in ipairs({ 'n <C-p>', 'n <leader>ttw', 'n <leader>hu', 'n <leader>nf', 'n <C-S-P>', 'n <C-S-N>' }) do
    if have[gone] then bad[#bad + 1] = gone .. ' still defined' end
  end
  for _, want in ipairs({ 'n <leader>[', 'n <leader>]' }) do
    if not have[want] then bad[#bad + 1] = want .. ' missing' end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

-- Theme: a palette is plain data; styling rules are the same for every part of the UI.
local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
local function hex(n) return n and ('#%06x'):format(n) or nil end

check.global('palette_files_valid', function()
  local files = vim.fn.globpath(root .. '/palettes', '*.json', false, true)
  if #files < 2 then return false, 'expected at least a dark and a light palette in palettes/' end
  local bad, variants = {}, {}
  for _, f in ipairs(files) do
    local ok, p = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), '\n'))
    if not ok then bad[#bad + 1] = f .. ': not JSON'
    else
      variants[p.variant or '?'] = true
      for i = 0, 15 do
        local key = ('base%02X'):format(i)
        if type(p[key]) ~= 'string' or not p[key]:match('^#%x%x%x%x%x%x$') then bad[#bad + 1] = vim.fs.basename(f) .. ': ' .. key end
      end
      if p.variant ~= 'dark' and p.variant ~= 'light' then bad[#bad + 1] = vim.fs.basename(f) .. ': variant' end
    end
  end
  if not (variants.dark and variants.light) then bad[#bad + 1] = 'need both a dark and a light palette' end
  return #bad == 0, table.concat(bad, ', ')
end)

-- Transparency is all-or-nothing: with it on, NO highlight group may paint one of
-- the palette's background shades (found by scanning every group, not a list).
check.global('ui_is_transparent', function()
  local theme = require('czernous.theme')
  if not (theme.current and theme.opts and theme.opts.transparent) then return false, 'theme.current / theme.opts.transparent missing' end
  if next(theme.shades or {}) == nil then return false, 'theme.shades is empty: the theme\'s background shades were not found' end
  -- make sure popup-owning plugins have defined their groups
  pcall(require, 'telescope'); pcall(require, 'which-key'); pcall(require, 'blink.cmp')
  vim.wait(200)
  local bad = {}
  for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
    if def.bg and theme.shades[def.bg] and not theme.is_accent(name) then bad[#bad + 1] = name end
  end
  -- and the surfaces you actually look at must have no background at all
  for _, name in ipairs({ 'Normal', 'NormalFloat', 'Pmenu', 'StatusLine', 'SignColumn', 'TelescopeNormal', 'WhichKeyNormal', 'BlinkCmpMenu', 'BlinkCmpDoc' }) do
    if hl(name).bg then bad[#bad + 1] = name .. ' (solid)' end
  end
  table.sort(bad)
  return #bad == 0, ('%d groups still paint a background: %s'):format(#bad, table.concat(bad, ', '):sub(1, 300))
end)

-- ...while the things you must see keep a background.
check.global('accents_keep_background', function()
  local theme = require('czernous.theme')
  local bad = {}
  for _, name in ipairs({ 'Visual', 'CursorLine', 'PmenuSel', 'Search', 'CurSearch', 'IncSearch' }) do
    if hl(name).bg == nil and not hl(name).reverse then bad[#bad + 1] = name end
    if not vim.tbl_contains(theme.accents or {}, name) then bad[#bad + 1] = name .. ' (not declared an accent)' end
  end
  return #bad == 0, 'no visible background: ' .. table.concat(bad, ', ')
end)

-- "The selected item" must look the same, and be clearly visible, everywhere:
-- every selection highlight uses the theme's own selection colour (Visual).
check.global('selection_is_visible_everywhere', function()
  local theme = require('czernous.theme')
  pcall(require, 'blink.cmp'); pcall(require, 'telescope'); pcall(require, 'which-key')
  vim.wait(300)
  local visual = hl('Visual').bg
  if not visual then return false, 'the theme has no selection (Visual) background' end
  local bad = {}
  for _, name in ipairs({ 'PmenuSel', 'BlinkCmpMenuSelection', 'TelescopeSelection', 'WildMenu', 'QuickFixLine' }) do
    if hl(name).bg ~= visual then bad[#bad + 1] = ('%s=%s'):format(name, hex(hl(name).bg) or 'none') end
  end
  return #bad == 0, ('selection colour is %s but: %s'):format(hex(visual), table.concat(bad, ', '))
end)

check.global('popups_have_borders', function()
  return vim.o.winborder ~= '' and vim.o.winborder ~= 'none', "winborder = '" .. vim.o.winborder .. "' (transparent popups need a border to be readable)"
end)

check.global('polarity_follows_background', function()
  local theme = require('czernous.theme')
  local start = theme.current and theme.current.name
  vim.o.background = 'light'; vim.wait(100)
  local light = theme.current and theme.current.variant
  local warned = false
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warned = true end return n(m, l, o) end
  theme.use('dark') -- the dark theme on a light terminal: must be refused
  vim.notify = n
  local still_light = theme.current and theme.current.variant
  vim.o.background = 'dark'; vim.wait(100)
  local dark = theme.current and theme.current.variant
  return light == 'light' and still_light == 'light' and warned and dark == 'dark',
    ('light bg -> %s; after use(dark) -> %s (warned=%s); dark bg -> %s; started on %s'):format(tostring(light), tostring(still_light), tostring(warned), tostring(dark), tostring(start))
end)

-- Transparency is all-or-nothing in BOTH directions: switched off, every surface
-- (editor, popups AND their borders, menus, picker, status line) is solid again.
check.global('toggle_restores_bg', function()
  local theme = require('czernous.theme')
  pcall(require, 'telescope'); pcall(require, 'blink.cmp'); pcall(require, 'which-key'); vim.wait(200)
  local surfaces = { 'Normal', 'NormalFloat', 'FloatBorder', 'Pmenu', 'StatusLine', 'TelescopeNormal', 'TelescopeBorder',
    'TelescopePromptNormal', 'TelescopePromptBorder', 'BlinkCmpMenu', 'BlinkCmpMenuBorder', 'BlinkCmpDoc', 'BlinkCmpDocBorder', 'WhichKeyNormal', 'WhichKeyBorder' }
  local function state()
    local solid, clear = {}, {}
    for _, name in ipairs(surfaces) do
      if hl(name).bg then solid[#solid + 1] = name else clear[#clear + 1] = name end
    end
    return solid, clear
  end
  theme.toggle_transparency()
  local _, clear_when_solid = state()
  theme.toggle_transparency()
  local solid_when_transparent = state()
  return #clear_when_solid == 0 and #solid_when_transparent == 0,
    ('switched off, still see-through: [%s]; switched back on, still solid: [%s]'):format(table.concat(clear_when_solid, ', '), table.concat(solid_when_transparent, ', '))
end)

-- The computed highlights are cached; a cached start must look exactly like a fresh one
-- and must not need the renderer plugin at all.
check.global('theme_cache_matches_fresh', function()
  local cache = vim.fn.tempname(); vim.fn.mkdir(cache, 'p')
  local function run()
    local r = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
      "autocmd VimEnter * ++once lua local t = {} for n, d in pairs(vim.api.nvim_get_hl(0, {})) do t[#t + 1] = n .. vim.inspect(d, { newline = '', indent = '' }) end table.sort(t) io.stdout:write('HL=' .. vim.fn.sha256(table.concat(t)) .. ' renderer=' .. tostring(package.loaded['catppuccin'] ~= nil) .. ' n=' .. #t) vim.cmd('qa!')" },
      { text = true, cwd = root, env = { XDG_CACHE_HOME = cache } }):wait(30000)
    local out = (r.stdout or '') .. (r.stderr or '')
    return out:match('HL=(%x+)'), out:match('renderer=(%a+)'), out
  end
  local fresh, r1, o1 = run()   -- empty cache: computed
  local cached, r2, o2 = run()  -- second start: from cache
  if not fresh or not cached then return false, 'no answer: ' .. (o1 .. o2):sub(1, 200) end
  return fresh == cached and r1 == 'true' and r2 == 'false',
    ('fresh %s (renderer loaded=%s) vs cached %s (renderer loaded=%s)'):format(fresh:sub(1, 8), r1, cached:sub(1, 8), r2)
end)

check.global('external_palette_used', function()
  local theme = require('czernous.theme')
  if not theme.load_file then return false, 'theme.load_file missing' end
  local f = vim.fn.tempname() .. '.json'
  local p = assert(theme.load_file(root .. '/palettes/onedark.json')); p.name = 'external-test'; p.base08 = '#123456'
  vim.fn.writefile({ vim.json.encode(p) }, f)
  local child = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua local c = require('czernous.theme').current io.stdout:write('PALETTE=' .. tostring(c.name) .. ' ' .. tostring(c.palette and c.palette.base08)) vim.cmd('qa!')" },
    { text = true, cwd = root, env = { NVIM_BASE16_PALETTE = f } }):wait(30000)
  local out = (child.stdout or '') .. (child.stderr or '')
  return out:find('PALETTE=base16%-external%-test #123456') ~= nil, out:sub(1, 200)
end)

check.global('special_buffers_are_quiet', function()
  local before = #check.errors
  for _, cmd in ipairs({ 'help help', 'Oil', 'terminal', 'enew' }) do
    vim.cmd('silent! %bwipeout!')
    local ok, err = pcall(vim.cmd, cmd)
    if not ok then return false, cmd .. ': ' .. tostring(err) end
    vim.wait(300)
  end
  return #check.errors == before, table.concat(check.errors, ' | ')
end)

check.global('format_command_matches_key', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  vim.wait(20000, function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end, 100)
  local fmt = require('czernous.format')
  local real, called = fmt.format, false
  fmt.format = function() called = true end
  local ok, err = pcall(vim.cmd, 'Format')
  fmt.format = real
  return ok and called, ok and ':Format did not use czernous.format' or tostring(err)
end)

check.global('treesitter_cli_lookup_cached', function()
  local before = check.exe_calls['tree-sitter'] or 0
  local nts = require('nvim-treesitter')
  local real = nts.install
  nts.install = function() return { await = function() end } end
  for _, ft in ipairs({ 'TelescopePrompt', 'qf', 'czunknown', 'TelescopePrompt' }) do
    vim.cmd('enew'); vim.bo.filetype = ft
  end
  nts.install = real
  local calls = (check.exe_calls['tree-sitter'] or 0) - before
  return calls == 0, ('tree-sitter looked up %d times'):format(calls)
end)

-- Grow selection somewhere new must start from the new place, not the old one.
check.global('incremental_selection_restarts_elsewhere', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  vim.api.nvim_win_set_cursor(0, { 2, 9 })
  vim.api.nvim_feedkeys(vim.keycode('<C-space><Esc>'), 'x', false)
  vim.api.nvim_win_set_cursor(0, { 5, 10 }) -- inside add(1, 2)
  vim.api.nvim_feedkeys(vim.keycode('v<C-space>'), 'x', false)
  local s, e = vim.fn.getpos('v')[2], vim.fn.getpos('.')[2]
  vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'x', false)
  return s == 5 and e == 5, ('selection lines %d-%d (want 5-5)'):format(s, e)
end)

-- Search keys look in the current file's project, not where Neovim started.
check.global('project_root_nearest', function()
  local ok, project = pcall(require, 'czernous.project')
  if not ok or not project.root then return false, 'czernous.project.root missing' end
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/mod/src/main/java', 'p')
  vim.fn.writefile({ '' }, dir .. '/settings.gradle.kts')
  vim.fn.writefile({ '' }, dir .. '/mod/build.gradle.kts')
  vim.fn.writefile({ 'class A {}' }, dir .. '/mod/src/main/java/A.java')
  local cases = {
    { fixtures .. '/go/main.go', fixtures .. '/go' },
    { fixtures .. '/rust/src/main.rs', fixtures .. '/rust' },
    { fixtures .. '/csharp/Program.cs', fixtures .. '/csharp' },
    { dir .. '/mod/src/main/java/A.java', dir },
    { root .. '/lua/czernous/init.lua', root }, -- falls back to the git root
  }
  local bad = {}
  for _, c in ipairs(cases) do
    vim.cmd('silent! %bwipeout!'); vim.cmd.edit(c[1])
    local got = project.root(0)
    if vim.fs.normalize(got) ~= vim.fs.normalize(c[2]) then bad[#bad + 1] = c[1] .. ' -> ' .. got end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('search_keys_use_project_root', function()
  local builtin = require('telescope.builtin')
  local saw = {}
  local real = {}
  for _, name in ipairs({ 'find_files', 'live_grep', 'grep_string' }) do
    real[name] = builtin[name]
    builtin[name] = function(opts) saw[name] = opts and opts.cwd end
  end
  local cwd = vim.fn.getcwd()
  vim.cmd.cd(vim.fn.tempname():match('^(.*)/')) -- somewhere unrelated
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/go/main.go')
  local fn = vim.fn.input
  vim.fn.input = function() return 'add' end
  for _, k in ipairs({ '<leader>pf', '<leader>pg', '<leader>ps' }) do vim.api.nvim_feedkeys(vim.keycode(k), 'x', false) end
  vim.fn.input = fn
  vim.cmd.cd(cwd)
  for name, f in pairs(real) do builtin[name] = f end
  local want = vim.fs.normalize(fixtures .. '/go')
  local bad = {}
  for _, name in ipairs({ 'find_files', 'live_grep', 'grep_string' }) do
    if not saw[name] or vim.fs.normalize(saw[name]) ~= want then bad[#bad + 1] = name .. ' cwd=' .. tostring(saw[name]) end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

-- Benchmarks must refuse to call unstable numbers a result.
check.global('bench_reports_instability', function()
  local ok, bench = pcall(dofile, root .. '/tests/bench.lua')
  if not ok or type(bench) ~= 'table' or not bench.compare then return false, 'tests/bench.lua has no compare(): ' .. tostring(bench) end
  local a = { startup_ms = { median = 100 }, open_ms = { go = { median = 50 } } }
  local far = { startup_ms = { median = 120 }, open_ms = { go = { median = 50 } } }
  local near = { startup_ms = { median = 105 }, open_ms = { go = { median = 52 } } }
  local s1, s2 = bench.compare(a, far), bench.compare(a, near)
  -- Real results carry min/median/max: stability is judged on the fastest run.
  local m1 = { startup_ms = { min = 100, median = 140, max = 200 } }
  local m_far = { startup_ms = { min = 125, median = 141, max = 150 } }
  local m_near = { startup_ms = { min = 104, median = 190, max = 300 } }
  local s3, s4 = bench.compare(m1, m_far), bench.compare(m1, m_near)
  -- A measure that failed in either pass is a disagreement, never silently "stable".
  local ok_pass = { completion_ms = { lua = { min = 70, median = 76, max = 90 } } }
  local err_pass = { completion_ms = { lua = { error = 'menu never appeared' } } }
  local s5, s6, s7 = bench.compare(err_pass, ok_pass), bench.compare(ok_pass, err_pass), bench.compare(err_pass, err_pass)
  local good = s1 == false and s2 == true and s3 == false and s4 == true and s5 == false and s6 == false and s7 == false
  return good, ('medians 20%%/5%% apart -> %s/%s (want false/true); mins 20%%/4%% apart -> %s/%s (want false/true); error in one/other/both passes -> %s/%s/%s (want all false)')
    :format(tostring(s1), tostring(s2), tostring(s3), tostring(s4), tostring(s5), tostring(s6), tostring(s7))
end)

---------------------------------------------------------------------------
-- Engineering standards (each proven by a tripwire: ./tests/check.sh --tripwires)
---------------------------------------------------------------------------
local allow = dofile(root .. '/tests/standards-allowlist.lua')

--- Lua source files that count as config code.
local function config_files()
  local files = vim.fn.globpath(root, 'lua/**/*.lua', false, true)
  vim.list_extend(files, vim.fn.globpath(root, 'after/**/*.lua', false, true))
  table.insert(files, root .. '/init.lua')
  if check.tripwire then vim.list_extend(files, vim.fn.globpath(root, 'tests/tripwires/**/*.lua', false, true)) end
  return files
end

--- Lines in config code matching any of `patterns` (comments stripped).
local function scan(patterns)
  local hits = {}
  for _, f in ipairs(config_files()) do
    for i, line in ipairs(vim.fn.readfile(f)) do
      local code = line:gsub('%-%-.*$', '')
      for _, pat in ipairs(patterns) do
        if code:find(pat) then hits[#hits + 1] = ('%s:%d (%s)'):format(f:sub(#root + 2), i, vim.trim(code):sub(1, 50)) end
      end
    end
  end
  return hits
end

-- No blocking calls at startup or on hot paths (each can cost ~100ms on slow $PATHs).
-- Runs LAST: it judges every call config code made during the whole run, including
-- what the formatting, statusline and start-screen checks exercised.
check.global('no_blocking_calls', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  local buf = vim.api.nvim_get_current_buf()
  check.hot = true
  for _, ev in ipairs({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'InsertCharPre', 'WinScrolled' }) do
    pcall(vim.api.nvim_exec_autocmds, ev, { buffer = buf, modeline = false })
  end
  pcall(vim.api.nvim_eval_statusline, vim.o.statusline, {})
  check.hot = false
  local function allowed(src, call)
    for _, entry in ipairs(allow.blocking) do
      if src:find(entry.file, 1, true) and call == entry.call then return true end
    end
    return false
  end
  local bad, seen = {}, {}
  -- 1. Calls seen while running (startup, hot paths, and everything after: lazily
  --    loaded plugin setup, FileType/LspAttach callbacks, ...).
  for _, c in ipairs(check.blocking) do
    local call = c.name:match('^[^(]+') -- 'vim.fn.executable(rg)' -> 'vim.fn.executable'
    local id = call .. '@' .. c.src
    if not allowed(c.src, call) and not seen[id] then
      seen[id] = true
      bad[#bad + 1] = ('%s at %s (%s)'):format(c.name, c.src, c.phase)
    end
  end
  -- 2. Calls present in the source, whether or not this run reached them, including
  --    spellings the recorder cannot see (vim.call, nvim_call_function, jobwait, :wait).
  local spellings = {
    ['vim.fn.executable'] = { 'fn%.executable%(' }, ['vim.fn.exepath'] = { 'fn%.exepath%(' },
    ['vim.fn.system'] = { 'fn%.system%(' }, ['vim.fn.systemlist'] = { 'fn%.systemlist%(' },
    ['io.popen'] = { 'io%.popen%(' }, ['os.execute'] = { 'os%.execute%(' },
    ['vim.system():wait()'] = { '%):wait%(', ':wait%(%d' }, ['vim.fn.jobwait'] = { 'jobwait%(' },
    ['vim.call'] = { 'vim%.call%(' }, ['nvim_call_function'] = { 'nvim_call_function%(' },
  }
  for call, patterns in pairs(spellings) do
    for _, hit in ipairs(scan(patterns)) do
      local file = hit:match('^[^:]+')
      if not allowed(file, call) then bad[#bad + 1] = call .. ' in ' .. hit end
    end
  end
  return #bad == 0, table.concat(bad, ', ')
end, { late = true })

check.global('no_global_writes', function()
  local bad = {}
  for _, g in ipairs(check.global_writes) do bad[#bad + 1] = g.name .. ' at ' .. g.src end
  vim.list_extend(bad, scan({ '_G%.[%w_]+%s*=', '_G%[' }))
  return #bad == 0, table.concat(bad, ', ')
end)

-- "Reflection": code that inspects or builds code at runtime.
check.global('no_reflection', function()
  -- the bare load() function, not a method or field called load (`plugin.load()`)
  local bad = scan({ 'debug%.', 'loadstring', '^%s*load%(', '[^%w_%.:]load%(', 'setfenv', 'getfenv' })
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('no_deprecated_api', function()
  local bad = scan({
    'vim%.loop', 'get_active_clients', 'buf_get_clients', 'diagnostic%.goto_', 'tbl_islist',
    'vim%.highlight%.on_yank', 'nvim_buf_get_option', 'nvim_buf_set_option', 'nvim_win_get_option',
    'nvim_win_set_option', 'vim%.lsp%.start_client', 'vim%.validate%(%s*{',
  })
  -- Neovim's own record of deprecated calls made this session.
  local ok, out = pcall(vim.api.nvim_exec2, 'checkhealth vim.deprecated', { output = true })
  if ok then
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find(root .. '/lua', 1, true) or line:find(root .. '/after', 1, true) or line:find('tests/tripwires', 1, true) then
        bad[#bad + 1] = vim.trim(line)
      end
    end
    vim.cmd('silent! bwipeout!')
  end
  return #bad == 0, table.concat(bad, ', ')
end)

-- State keyed by a buffer must go away with the buffer. Open and wipe many
-- buffers, then walk everything reachable from config code (modules, autocmd
-- and keymap callbacks, their upvalues) for tables still keyed by a dead buffer.
check.global('no_buffer_state_leaks', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.system({ 'git', 'init', '-q', dir }) -- so git integration attaches too
  local dead = {}
  vim.cmd('silent! %bwipeout!')
  -- Push buffer numbers past 5000 first, so "a key that is a dead buffer's number"
  -- can't be confused with a position in an ordinary list (item 3 of 30, ...).
  local burn = {}
  repeat burn[#burn + 1] = vim.api.nvim_create_buf(false, true) until burn[#burn] >= 5000
  for _, b in ipairs(burn) do vim.api.nvim_buf_delete(b, { force = true }) end
  for i = 1, 40 do
    local f = ('%s/f%d.lua'):format(dir, i)
    vim.fn.writefile({ 'local function add(a, b)', '  return a + b', 'end', '', 'print(add(1, 2))' }, f)
    vim.cmd.edit(f)
    local buf = vim.api.nvim_get_current_buf()
    -- Neovim's LSP startup touches the buffer on the next tick (and errors if it is
    -- already gone); give it that tick, as any human-paced use would.
    vim.wait(30)
    -- The first few buffers wait for the language server and git signs, so the
    -- LspAttach / on_attach code paths (and their per-buffer state) run as well.
    if i <= 4 then
      vim.wait(6000, function() return #vim.lsp.get_clients({ bufnr = buf }) > 0 end, 50)
      vim.wait(1500, function() return vim.b[buf].gitsigns_status_dict ~= nil end, 50)
    end
    vim.api.nvim_win_set_cursor(0, { 2, 9 })
    vim.api.nvim_feedkeys(vim.keycode('<C-space><C-space><Esc>'), 'x', false)
    vim.cmd('doautocmd CursorMoved'); vim.cmd('doautocmd InsertEnter'); vim.cmd('doautocmd InsertLeave')
    vim.cmd('enew'); vim.cmd('silent! bwipeout! ' .. buf)
    dead[buf] = true
  end
  vim.wait(300)
  collectgarbage('collect'); collectgarbage('collect')

  -- Never descend into Neovim's or plugins' own tables (reachable when config code
  -- keeps e.g. `local lsp = vim.lsp`): their state is not ours to judge.
  local seen, leaks = {}, {}
  seen[_G], seen[vim], seen[dead] = true, true, true
  for name, mod in pairs(package.loaded) do
    if type(mod) == 'table' and not (type(name) == 'string' and name:match('^czernous')) then seen[mod] = true end
  end
  for _, field in pairs(vim) do if type(field) == 'table' then seen[field] = true end end
  local function walk(v, path, depth)
    if depth > 12 or seen[v] then return end
    local t = type(v)
    if t == 'table' then
      seen[v] = true
      -- Weak tables are NOT exempt: number keys are never collected from them.
      local hits = 0
      for k, val in pairs(v) do
        if type(k) == 'number' and dead[k] then hits = hits + 1 end
        if type(val) == 'table' or type(val) == 'function' then walk(val, path .. '.' .. tostring(k), depth + 1) end
      end
      if hits >= 5 then leaks[#leaks + 1] = ('%s holds %d entries for wiped buffers'):format(path, hits) end
    elseif t == 'function' then
      seen[v] = true
      local info = debug.getinfo(v, 'S')
      if classify(info.source:gsub('^@', '')) ~= 'user' then return end
      local i = 1
      while true do
        local name, up = debug.getupvalue(v, i)
        if not name then break end
        if type(up) == 'table' or type(up) == 'function' then walk(up, path .. ':' .. name, depth + 1) end
        i = i + 1
      end
    end
  end
  for name, mod in pairs(package.loaded) do
    if type(name) == 'string' and name:match('^czernous') then walk(mod, name, 0) end
  end
  for _, au in ipairs(vim.api.nvim_get_autocmds({})) do
    if type(au.callback) == 'function' then walk(au.callback, 'autocmd ' .. au.event, 0) end
  end
  for _, mode in ipairs({ 'n', 'x', 's', 'i', 'o', 'c', 't' }) do
    for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
      if type(km.callback) == 'function' then walk(km.callback, 'keymap ' .. km.lhs, 0) end
    end
  end
  return #leaks == 0, table.concat(leaks, '; ')
end)

-- Step-1 leftovers.
check.global('csharp_fixture_unpinned', function()
  local text = table.concat(vim.fn.readfile(fixtures .. '/csharp/fixture.csproj'), '\n')
  return not text:find('>net%d'), 'fixture.csproj names a specific .NET version'
end)

-- A server installed with :MasonInstall mid-session starts without a restart.
check.global('mason_install_enables_server', function()
  local lsp = require('czernous.lsp')
  if vim.tbl_contains(lsp.enabled, 'vtsls') then return 'skip', 'vtsls already installed here' end
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, dir .. '/vtsls'); vim.fn.setfperm(dir .. '/vtsls', 'rwxr-xr-x')
  local old = vim.env.PATH; vim.env.PATH = dir .. ':' .. old
  vim.cmd('enew'); vim.bo.filetype = 'mason' -- what opening the Mason window does
  require('mason-registry'):emit('package:install:success', {})
  vim.wait(8000, function() return vim.tbl_contains(lsp.enabled, 'vtsls') end, 50)
  local ok = vim.tbl_contains(lsp.enabled, 'vtsls')
  vim.env.PATH = old
  if ok then
    vim.lsp.enable('vtsls', false)
    lsp.enabled = vim.tbl_filter(function(n) return n ~= 'vtsls' end, lsp.enabled)
  end
  vim.cmd('silent! bwipeout!')
  return ok, 'vtsls not enabled after a Mason install event'
end)

---------------------------------------------------------------------------
-- Startup: nothing loads before the first screen except the theme
---------------------------------------------------------------------------
--- Run a child Neovim with this config and a Lua probe; returns its stdout+stderr.
local function child_nvim(probe_lines, args, timeout)
  local probe = vim.fn.tempname() .. '.lua'
  vim.fn.writefile(probe_lines, probe)
  local cmd = { vim.v.progpath, '--headless', '-n', '--cmd', 'luafile ' .. probe }
  vim.list_extend(cmd, args or {})
  local r = vim.system(cmd, { text = true, cwd = root }):wait(timeout or 40000)
  return (r.stdout or '') .. (r.stderr or '')
end

check.global('only_theme_loads_at_startup', function()
  local trip = check.tripwire == 'eager'
  local out = child_nvim({
    trip and ("vim.opt.runtimepath:prepend('" .. root .. "/tests/tripwires'); require('czernous.tripwire_eager')") or '',
    "vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()",
    "  local names = {}",
    "  for name, p in pairs(require('lazy.core.config').plugins) do if p._.loaded then names[#names + 1] = name end end",
    "  table.sort(names); io.stdout:write('LOADED=' .. table.concat(names, ',') .. '\\n'); vim.cmd('qa!')",
    "end })",
  })
  local loaded = out:match('LOADED=([^\n]*)')
  if not loaded then return false, 'child gave no answer: ' .. out:sub(1, 200) end
  -- the colour-scheme plugins may load (only when the theme cache is being rebuilt)
  local allowed = { ['lazy.nvim'] = true, catppuccin = true, ['mini.base16'] = true }
  local extra = {}
  for name in loaded:gmatch('[^,]+') do
    if not allowed[name] then extra[#extra + 1] = name end
  end
  return #extra == 0, ('loaded before the first screen: %s%s'):format(table.concat(extra, ', '), trip and ' [tripwire eager active]' or '')
end)

-- Generous ceiling (target is ~5 ms over bare Neovim): catches a regression like
-- the 1 s one found in step 1 without failing on a noisy machine.
check.global('launch_within_budget', function()
  local bench = dofile(root .. '/tests/bench.lua')
  local function fastest(args)
    local best = math.huge
    for _ = 1, 21 do best = math.min(best, bench.ready_ms(args) or math.huge) end
    return best
  end
  -- spawn -> ready (shutdown excluded), config vs bare Neovim. Noise only ever adds
  -- time, so the fastest run is what counts: re-measure (up to 3 rounds) before
  -- calling it a failure.
  local bare, config = math.huge, math.huge
  for _ = 1, 3 do
    bare, config = math.min(bare, fastest({ '-u', 'NONE' })), math.min(config, fastest({}))
    if config - bare <= 12 then break end
  end
  return config - bare <= 12, ('ready in %.1f ms vs bare %.1f ms: config adds %.1f ms (budget 12)'):format(config, bare, config - bare)
end, { early = true })

-- Lazily loaded plugins must work from every way in.
check.global('lazy_entry_points', function()
  local out = child_nvim({
    "vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()",
    "  local res = {}",
    "  vim.api.nvim_feedkeys(vim.keycode('<leader>pf'), 'x', false)", -- a key, immediately
    "  res[#res + 1] = 'key=' .. tostring(package.loaded['telescope'] ~= nil)",
    "  pcall(vim.cmd, 'stopinsert'); pcall(vim.cmd, 'silent! close')",
    "  res[#res + 1] = 'gitcmd=' .. vim.fn.exists(':Git')",
    "  local ok = pcall(vim.cmd, 'silent Git --version')",
    "  res[#res + 1] = 'git=' .. tostring(ok and vim.fn.exists('*FugitiveGitDir') == 1)",
    "  res[#res + 1] = 'ts=' .. tostring(vim.treesitter.highlighter.active[vim.fn.bufnr('main.go')] ~= nil)",
    "  local ok2 = pcall(vim.cmd, 'Telescope builtin')",
    "  res[#res + 1] = 'cmd=' .. tostring(ok2)",
    "  io.stdout:write('ENTRY ' .. table.concat(res, ' ') .. ' msgs=' .. vim.api.nvim_exec2('messages', { output = true }).output:gsub('\\n', ' | '):sub(1, 200) .. '\\n')",
    "  vim.cmd('qa!')",
    "end })",
  }, { fixtures .. '/go/main.go' })
  local line = out:match('ENTRY ([^\n]*)') or ('no answer: ' .. out:sub(1, 300))
  local good = line:find('key=true') and line:find('gitcmd=2') and line:find('git=true') and line:find('ts=true') and line:find('cmd=true')
    and not line:find('E%d+:') and not line:find('not found')
  return good ~= nil and good ~= false, line
end)

---------------------------------------------------------------------------
-- Completion
---------------------------------------------------------------------------
check.global('completion_menu_appears', function()
  if vim.fn.executable('lua-language-server') == 0 then return 'skip', 'lua-language-server not on PATH' end
  local bench = dofile(root .. '/tests/bench.lua')
  -- real terminal UI in a pty child: type `pri`, wait for the menu, accept with Enter
  local r = bench.completion(fixtures .. '/lua/init.lua', 'pri', '<Esc>Go', 3, nil, true)
  if r.error then return false, r.error end
  local line = vim.trim(r.accepted or '')
  return r.median < 500 and line:find('^print') ~= nil,
    ('menu after %.0f ms (want < 500); Enter inserted %q (want print...)'):format(r.median, line)
end)

check.global('completion_engine_is_blink', function()
  local lock = table.concat(vim.fn.readfile(root .. '/lazy-lock.json'), '\n')
  local bad = {}
  for _, gone in ipairs({ '"nvim-cmp"', '"LuaSnip"', '"cmp_luasnip"', '"cmp-nvim-lsp"', '"cmp-path"' }) do
    if lock:find(gone, 1, true) then bad[#bad + 1] = gone .. ' still in lockfile' end
  end
  if not lock:find('"blink.cmp"', 1, true) then bad[#bad + 1] = 'blink.cmp not in lockfile' end
  local caps = vim.lsp.config['*'] and vim.lsp.config['*'].capabilities or {}
  if not vim.tbl_get(caps, 'textDocument', 'completion', 'completionItem', 'snippetSupport') then
    bad[#bad + 1] = 'LSP capabilities do not advertise snippet support'
  end
  -- pure-Lua fuzzy matcher: no native binary downloaded or built
  local so = vim.fn.globpath(vim.fn.stdpath('data') .. '/lazy/blink.cmp', 'target/**/*.so', false, true)
  if #so > 0 then bad[#bad + 1] = 'native binary present: ' .. so[1] end
  return #bad == 0, table.concat(bad, '; ')
end)

---------------------------------------------------------------------------
-- Statusline: built in, informative, and free while you move around
---------------------------------------------------------------------------
local function rendered_statusline()
  return vim.api.nvim_eval_statusline(vim.o.statusline, {}).str
end

check.global('statusline_native', function()
  local lock = table.concat(vim.fn.readfile(root .. '/lazy-lock.json'), '\n')
  if lock:find('lualine', 1, true) then return false, 'lualine still in lockfile' end
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  vim.api.nvim_win_set_cursor(0, { 2, 3 }); vim.wait(100)
  local text = rendered_statusline()
  local ok = text:find('NORMAL') and text:find('init.lua', 1, true) and text:find('2:4', 1, true) and text:find('lua', 1, true)
  return ok ~= nil, 'rendered: [' .. text .. '] (want mode, file name, filetype, 2:4)'
end)

-- On a normal (cached-theme) start the statusline must already have its real
-- colours: text = the theme's text colour, branch/filetype = its comment colour.
check.global('statusline_colours_at_startup', function()
  local r = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua local function fg(n) return tostring(vim.api.nvim_get_hl(0, { name = n, link = false }).fg) end io.stdout:write(('COLOURS normal=%s text=%s comment=%s dim=%s cached=%s'):format(fg('Normal'), fg('CzStlText'), fg('Comment'), fg('CzStlDim'), tostring(package.loaded['catppuccin'] == nil))) vim.cmd('qa!')" },
    { text = true, cwd = root }):wait(30000)
  local out = (r.stdout or '') .. (r.stderr or '')
  local normal, text, comment, dim, cached = out:match('normal=(%S+) text=(%S+) comment=(%S+) dim=(%S+) cached=(%S+)')
  if not normal then return false, 'no answer: ' .. out:sub(1, 200) end
  return normal ~= 'nil' and text == normal and dim == comment and cached == 'true',
    ('Normal fg=%s, statusline text=%s; Comment fg=%s, statusline dim=%s; started from cache=%s'):format(normal, text, comment, dim, cached)
end)

-- Start screen: shown only when Neovim starts with no file; gone once you open one.
check.global('start_screen', function()
  local function run(args)
    local cmd = { vim.v.progpath, '--headless', '-n', '--cmd',
      "autocmd VimEnter * ++once lua vim.defer_fn(function() local l = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|') io.stdout:write('SCREEN ft=' .. (vim.b.czernous_start and 'czstart' or vim.bo.filetype) .. ' mod=' .. tostring(vim.bo.modified) .. ' text=' .. l:gsub('%s+', ' '):sub(1, 900)) vim.cmd('qa!') end, 150)" }
    vim.list_extend(cmd, args)
    local r = vim.system(cmd, { text = true, cwd = root }):wait(30000)
    return (r.stdout or '') .. (r.stderr or '')
  end
  local empty, with_file, with_dir = run({}), run({ fixtures .. '/lua/init.lua' }), run({ '.' })
  local function is_start(out)
    return out:find('ft=czstart') and out:find('ready in [%d%.]+ ms') and out:find('find file', 1, true) and out:find('mod=false')
  end
  local absent = with_file:find('ft=lua') and not with_file:find('ready in')
  -- `nvim .` (a folder, the owner's usual way in) gets the start screen too, not the file explorer
  return (is_start(empty) and is_start(with_dir) and absent) and true or false,
    ('no args: %s || `nvim .`: %s || with file: %s'):format(empty:sub(1, 60), with_dir:sub(1, 90), with_file:sub(1, 40))
end)

check.global('statusline_shows_problems_and_branch', function()
  -- a file outside any git repo, so the branch shown is the one set below
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'local a = 1', 'local b = 2', 'return a + b' }, dir .. '/s.lua')
  vim.o.columns = 140
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/s.lua')
  local buf = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace('czcheck_stl')
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, message = 'e1', severity = vim.diagnostic.severity.ERROR },
    { lnum = 1, col = 0, message = 'e2', severity = vim.diagnostic.severity.ERROR },
    { lnum = 2, col = 0, message = 'w1', severity = vim.diagnostic.severity.WARN },
    { lnum = 2, col = 0, message = 'h1', severity = vim.diagnostic.severity.HINT },
  })
  vim.b[buf].gitsigns_head = 'feature/x%y'
  vim.api.nvim_exec_autocmds('User', { pattern = 'GitSignsUpdate', modeline = false })
  vim.wait(150)
  local text = rendered_statusline()
  vim.diagnostic.reset(ns, buf)
  local ok = text:find('E2', 1, true) and text:find('W1', 1, true) and text:find('H1', 1, true) and text:find('git:feature/x%y', 1, true)
  -- plain text only: nothing outside ASCII, so it renders in any font
  ok = ok and not text:find('[\128-\255]')
  return ok ~= nil, 'rendered: [' .. text .. '] (want E2, W1 and the branch, with % shown literally)'
end)

check.global('statusline_special_buffers', function()
  local before = #check.errors
  for _, cmd in ipairs({ 'help help', 'Oil', 'terminal', 'enew' }) do
    vim.cmd('silent! %bwipeout!')
    local ok, err = pcall(vim.cmd, cmd)
    if not ok then return false, cmd .. ': ' .. tostring(err) end
    vim.wait(150)
    local ok2, text = pcall(rendered_statusline)
    if not ok2 or text == '' then return false, cmd .. ': statusline failed: ' .. tostring(text) end
  end
  check.snapshot_messages()
  return #check.errors == before, table.concat(check.errors, ' | '):sub(1, 200)
end)

-- Moving the cursor must cost the statusline nothing: no handlers on cursor
-- events, and drawing it runs no Lua (so allocates nothing).
check.global('statusline_is_cheap', function()
  local bad = {}
  for _, ev in ipairs({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'WinScrolled' }) do
    for _, au in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
      if au.group_name == 'czernous_statusline' then bad[#bad + 1] = ev .. ' handler (' .. tostring(au.desc) .. ')' end
    end
  end
  if vim.o.statusline:find('v:lua', 1, true) or vim.o.statusline:find('%{', 1, true) then
    bad[#bad + 1] = 'statusline evaluates code on every redraw: ' .. vim.o.statusline:sub(1, 60)
  end
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua'); vim.wait(100)
  for _ = 1, 30 do rendered_statusline() end
  collectgarbage('collect'); collectgarbage('collect'); collectgarbage('stop')
  local b = collectgarbage('count')
  for _ = 1, 500 do rendered_statusline() end
  local per = (collectgarbage('count') - b) * 1024 / 500
  collectgarbage('restart')
  -- nvim_eval_statusline itself returns a table+string (~150 B); the config may add nothing on top
  if per > 400 then bad[#bad + 1] = ('%d B allocated per redraw'):format(per) end
  return #bad == 0, table.concat(bad, '; ')
end)

-- K shows documentation from the language server; with no server it must say so
-- (naming the language) instead of failing silently.
check.global('hover_key_explains_missing_server', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd('enew'); vim.bo.filetype = 'kotlin'
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then return 'skip', 'a Kotlin language server is installed here' end
  local before, said = #check.errors, nil
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN or l == vim.log.levels.INFO then said = tostring(m) end return n(m, l, o) end
  local ok = pcall(vim.api.nvim_feedkeys, 'K', 'x', false)
  vim.notify = n
  check.snapshot_messages()
  local explained = said and said:lower():find('kotlin', 1, true) and said:lower():find('language server', 1, true)
  -- and with a server attached K still opens the documentation popup
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  vim.wait(20000, function() local c = vim.lsp.get_clients({ bufnr = 0 })[1]; return c and c:supports_method('textDocument/hover', 0) end, 100)
  vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- on `print`
  local wins = #vim.api.nvim_list_wins()
  vim.api.nvim_feedkeys('K', 'x', false)
  vim.wait(4000, function() return #vim.api.nvim_list_wins() > wins end, 50)
  local hovered = #vim.api.nvim_list_wins() > wins
  vim.cmd('silent! only')
  return (ok and explained and hovered and #check.errors == before) and true or false,
    ('no server: said %q; with server: popup opened=%s'):format(tostring(said), tostring(hovered))
end)

check.global('kotlin_server_known', function()
  local servers = require('czernous.lsp').servers
  return servers.kotlin_language_server ~= nil or servers.kotlin_lsp ~= nil, 'no Kotlin entry in lsp.servers'
end)

---------------------------------------------------------------------------
-- Formatting: <leader>f = the project's formatter (conform) or the language
-- server; <leader>F = exact Spotless in Gradle projects that use it.
---------------------------------------------------------------------------
--- Fake Gradle project whose ./gradlew behaves like the Spotless IDE hook.
local function fake_spotless_project(script, build_file)
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile({ build_file or 'plugins { id("com.diffplug.spotless") }' }, dir .. '/build.gradle.kts')
  vim.fn.writefile(script, dir .. '/gradlew'); vim.fn.setfperm(dir .. '/gradlew', 'rwxr-xr-x')
  vim.fn.writefile({ 'hello', 'world' }, dir .. '/src/x.txt')
  return dir
end

--- Run fn while counting WARN notifications; returns count.
local function count_warnings(fn)
  local warned = 0
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warned = warned + 1 end return n(m, l, o) end
  local ok, err = pcall(fn)
  vim.notify = n
  return warned, ok, err
end

check.global('format_uses_project_formatter', function()
  -- a formatter program on $PATH (here a fake `stylua` that upper-cases) is used for its filetype
  local bin = vim.fn.tempname(); vim.fn.mkdir(bin, 'p')
  vim.fn.writefile({ '#!/bin/sh', 'tr a-z A-Z' }, bin .. '/stylua'); vim.fn.setfperm(bin .. '/stylua', 'rwxr-xr-x')
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'local a = 1' }, dir .. '/f.lua')
  local old = vim.env.PATH; vim.env.PATH = bin .. ':' .. old
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/f.lua')
  require('czernous.format').format()
  vim.wait(5000, function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'LOCAL A = 1' end, 50)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  vim.env.PATH = old
  vim.cmd('silent! bwipeout!')
  return line == 'LOCAL A = 1', 'buffer is ' .. vim.inspect(line)
end)

check.global('format_without_any_formatter_says_so', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd('enew'); vim.bo.filetype = 'czunknownlang'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x' })
  local before = #check.errors
  local warned, ok = count_warnings(function() require('czernous.format').format(); vim.wait(500) end)
  check.snapshot_messages()
  vim.cmd('silent! bwipeout!')
  return ok and warned == 1 and #check.errors == before, ('ok=%s warnings=%d errors=%d'):format(tostring(ok), warned, #check.errors - before)
end)

check.global('format_does_not_run_gradle', function()
  -- <leader>f must stay instant in Spotless projects: Gradle only runs on <leader>F
  local dir = fake_spotless_project({ '#!/bin/sh', 'touch "$0.ran"', 'cat >/dev/null', 'echo "IS CLEAN" >&2' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  count_warnings(function() require('czernous.format').format(); vim.wait(800) end)
  return vim.fn.filereadable(dir .. '/gradlew.ran') == 0, 'gradlew was run by <leader>f'
end)

check.global('spotless_formats_exactly', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'echo "IS DIRTY" >&2', 'tr a-z A-Z' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  require('czernous.format').spotless()
  vim.wait(5000, function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO' end, 50)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return vim.deep_equal(lines, { 'HELLO', 'WORLD' }), vim.inspect(lines)
end)

check.global('spotless_clean_is_noop', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'cat >/dev/null', 'echo "IS CLEAN" >&2' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  require('czernous.format').spotless()
  vim.wait(1500)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return vim.deep_equal(lines, { 'hello', 'world' }) and not vim.bo.modified, vim.inspect(lines)
end)

check.global('spotless_failures_warn_and_keep_buffer', function()
  local cases = {
    { 'gradle fails', { '#!/bin/sh', 'cat >/dev/null', 'echo "BUILD FAILED" >&2', 'exit 1' } },
    { 'says dirty but returns nothing', { '#!/bin/sh', 'cat >/dev/null', 'echo "IS DIRTY" >&2' } },
    { 'file not covered by Spotless', { '#!/bin/sh', 'cat >/dev/null', 'exit 0' } },
  }
  local bad = {}
  for _, c in ipairs(cases) do
    local dir = fake_spotless_project(c[2])
    vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
    local before = #check.errors
    local warned = count_warnings(function() require('czernous.format').spotless(); vim.wait(1500) end)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if warned ~= 1 or #check.errors ~= before or not vim.deep_equal(lines, { 'hello', 'world' }) then
      bad[#bad + 1] = ('%s: warnings=%d errors=%d lines=%s'):format(c[1], warned, #check.errors - before, vim.inspect(lines))
    end
  end
  return #bad == 0, table.concat(bad, '; ')
end)

check.global('spotless_key_outside_spotless_project_warns', function()
  local bad = {}
  -- a plain file, an unnamed buffer inside a Spotless project folder, a non-executable gradlew
  local plain = vim.fn.tempname() .. '.txt'; vim.fn.writefile({ 'x' }, plain)
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(plain)
  if count_warnings(function() require('czernous.format').spotless(); vim.wait(300) end) ~= 1 then bad[#bad + 1] = 'plain file: no single warning' end
  local dir = fake_spotless_project({ '#!/bin/sh', 'touch "$0.ran"', 'cat >/dev/null', 'echo "IS CLEAN" >&2' })
  local cwd = vim.fn.getcwd()
  vim.cmd('silent! %bwipeout!'); vim.cmd.cd(dir); vim.cmd('enew')
  local w = count_warnings(function() require('czernous.format').spotless(); vim.wait(600) end)
  vim.cmd.cd(cwd)
  if w ~= 1 or vim.fn.filereadable(dir .. '/gradlew.ran') == 1 then bad[#bad + 1] = 'unnamed buffer: warnings=' .. w .. ' or gradlew ran' end
  local dir2 = fake_spotless_project({ '#!/bin/sh', 'exit 0' }); vim.fn.setfperm(dir2 .. '/gradlew', 'rw-r--r--')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir2 .. '/src/x.txt')
  local before = #check.errors
  local w2, ok = count_warnings(function() require('czernous.format').spotless(); vim.wait(600) end)
  if w2 ~= 1 or not ok or #check.errors ~= before then bad[#bad + 1] = ('non-executable gradlew: warnings=%d ok=%s'):format(w2, tostring(ok)) end
  return #bad == 0, table.concat(bad, '; ')
end)

check.global('spotless_in_subproject_detected', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'echo "IS DIRTY" >&2', 'tr a-z A-Z' }, 'plugins { java }')
  vim.fn.mkdir(dir .. '/mod/src', 'p')
  vim.fn.writefile({ 'plugins { id("com.diffplug.spotless") }' }, dir .. '/mod/build.gradle.kts')
  vim.fn.writefile({ 'hello' }, dir .. '/mod/src/y.txt')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/mod/src/y.txt')
  require('czernous.format').spotless()
  vim.wait(5000, function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO' end, 50)
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO', 'Spotless declared in a module build file was not used'
end)

-- Java: jdtls formats with the project's own Eclipse formatter file (the one Spotless uses).
check.global('eclipse_formatter_profile_found', function()
  local fmt = require('czernous.format')
  if not fmt.eclipse_profile then return false, 'format.eclipse_profile missing' end
  local function project(build, files)
    local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
    vim.fn.writefile({ build }, dir .. '/build.gradle.kts')
    for _, f in ipairs(files) do vim.fn.mkdir(vim.fn.fnamemodify(dir .. '/' .. f, ':h'), 'p'); vim.fn.writefile({ '<profiles/>' }, dir .. '/' .. f) end
    return dir
  end
  local a = project('spotless { java { eclipse().configFile(rootProject.file("config/fmt.xml")) } }', { 'config/fmt.xml' })
  local b = project('plugins { java }', { 'config/eclipse-formatter.xml' })
  local c = project('plugins { java }', {})
  local d = project('spotless { java { eclipse().configFile("missing.xml") } }', {})
  local ra, rb, rc, rd = fmt.eclipse_profile(a), fmt.eclipse_profile(b), fmt.eclipse_profile(c), fmt.eclipse_profile(d)
  local ok = ra == a .. '/config/fmt.xml' and rb == b .. '/config/eclipse-formatter.xml' and rc == nil and rd == nil
  return ok, ('declared -> %s; conventional -> %s; none -> %s; declared but missing -> %s'):format(tostring(ra), tostring(rb), tostring(rc), tostring(rd))
end)

check.global('formatter_plugins', function()
  local lock = table.concat(vim.fn.readfile(root .. '/lazy-lock.json'), '\n')
  return lock:find('"conform.nvim"', 1, true) ~= nil and not lock:find('"neoformat"', 1, true), 'want conform.nvim in the lockfile and neoformat gone'
end)

---------------------------------------------------------------------------
-- Stage 2a clean-up: replaced plugins gone, built-ins used, options, keys
---------------------------------------------------------------------------
local function has_key(mode, lhs)
  for _, k in ipairs(require('czernous.keymaps').all()) do
    if k.mode == mode and k.lhs == lhs then return k end
  end
end

check.global('dropped_plugins_gone', function()
  local lock = table.concat(vim.fn.readfile(root .. '/lazy-lock.json'), '\n')
  local bad = {}
  for _, name in ipairs({ 'telescope-fzf-native.nvim', 'vim-rhubarb', 'undotree', 'trouble.nvim', 'nvim-web-devicons', 'neoformat', 'lualine.nvim' }) do
    if lock:find('"' .. name .. '"', 1, true) then bad[#bad + 1] = name end
  end
  if not lock:find('"oil.nvim"', 1, true) then bad[#bad + 1] = 'oil.nvim missing' end
  if vim.uv.fs_stat(root .. '/lua/czernous/incremental_selection.lua') then bad[#bad + 1] = 'incremental_selection.lua still exists' end
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('options_set', function()
  local want = { undofile = true, ignorecase = true, smartcase = true, scrolloff = 8, splitright = true, splitbelow = true,
    inccommand = 'split', cursorline = true, confirm = true, smartindent = false }
  local bad = {}
  for name, value in pairs(want) do
    -- the global value: what every new window gets
    if vim.go[name] ~= value then bad[#bad + 1] = ('%s=%s'):format(name, tostring(vim.go[name])) end
  end
  if vim.o.guicursor == '' then bad[#bad + 1] = 'guicursor is empty (block cursor in every mode)' end
  return #bad == 0, table.concat(bad, ', ')
end)

-- The start screen's bare look must not leak into other windows.
check.global('start_screen_does_not_change_defaults', function()
  local out = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua vim.defer_fn(function() local on_start = vim.b.czernous_start and 'czstart' or vim.bo.filetype vim.cmd('split') vim.cmd('enew') io.stdout:write(('START=%s global: number=%s cursorline=%s | new window: number=%s cursorline=%s signcolumn=%s'):format(on_start, tostring(vim.go.number), tostring(vim.go.cursorline), tostring(vim.wo.number), tostring(vim.wo.cursorline), vim.wo.signcolumn)) vim.cmd('qa!') end, 200)" },
    { text = true, cwd = root }):wait(30000)
  local text = (out.stdout or '') .. (out.stderr or '')
  local ok = text:find('START=czstart') and text:find('global: number=true cursorline=true') and text:find('new window: number=true cursorline=true signcolumn=yes')
  return ok ~= nil, text:sub(1, 220)
end)

check.global('explorer_is_oil', function()
  if vim.fn.exists(':Explore') == 2 then return false, 'the built-in explorer (netrw) is still loaded' end
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p'); vim.fn.writefile({ 'x' }, dir .. '/a.txt')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/a.txt')
  vim.api.nvim_feedkeys(vim.keycode('<leader>pv'), 'x', false)
  vim.wait(2000, function() return vim.bo.filetype == 'oil' end, 50)
  local ft = vim.bo.filetype
  vim.wait(500)
  local listing = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')
  vim.cmd('silent! %bwipeout!')
  -- plain names only: no icon column (font independence)
  return ft == 'oil' and listing:find('a.txt', 1, true) ~= nil and not listing:find('[\128-\255]'), ('filetype=%s listing=%s'):format(ft, listing:sub(1, 80))
end)

-- The explorer must open fast, including the very first time (the built-in one
-- took ~700 ms on first open here), and must show its key hints.
check.global('explorer_opens_fast_with_hints', function()
  local r = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua vim.defer_fn(function() vim.cmd.edit('lua/czernous/theme.lua') local t0 = vim.uv.hrtime() vim.api.nvim_feedkeys(vim.keycode('<leader>pv'), 'x', false) vim.wait(3000, function() return vim.bo.filetype == 'oil' and vim.api.nvim_buf_line_count(0) > 1 end, 1) io.stdout:write(('OPEN=%.0f HINT=%s'):format((vim.uv.hrtime() - t0) / 1e6, tostring(vim.wo.winbar:find('rename', 1, true) ~= nil and vim.wo.winbar:find('delete', 1, true) ~= nil))) vim.cmd('qa!') end, 300)" },
    { text = true, cwd = root }):wait(30000)
  local out = (r.stdout or '') .. (r.stderr or '')
  local ms = tonumber(out:match('OPEN=(%d+)'))
  return ms ~= nil and ms < 200 and out:find('HINT=true') ~= nil, out:sub(1, 120) .. ' (want first open < 200 ms and the key hints shown)'
end)

check.global('builtin_undotree_key', function()
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  local wins = #vim.api.nvim_list_wins()
  local ok, err = pcall(vim.api.nvim_feedkeys, vim.keycode('<leader>u'), 'x', false)
  vim.wait(500)
  local opened = #vim.api.nvim_list_wins() > wins
  vim.cmd('silent! only')
  return ok and opened, ('ok=%s opened a window=%s %s'):format(tostring(ok), tostring(opened), tostring(err or ''))
end)

check.global('clipboard_keys_in_visual', function()
  local bad = {}
  for _, lhs in ipairs({ '<leader>y', '<leader>d' }) do
    if not has_key('x', lhs) and not has_key('v', lhs) then bad[#bad + 1] = lhs .. ' missing in visual mode' end
    if not has_key('n', lhs) then bad[#bad + 1] = lhs .. ' missing in normal mode' end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('removed_keys_gone', function()
  local bad = {}
  for _, k in ipairs({ { 'n', 'Y' }, { 'n', '<C-k>' }, { 'n', '<C-j>' }, { 'n', '<leader>k' }, { 'n', '<leader>j' }, { 'n', '<leader>vd' },
    { 'n', '[d' }, { 'n', ']d' }, { 'n', '<leader>wa' }, { 'n', '<leader>wr' }, { 'n', '<leader>wl' }, { 'n', '<leader>ttx' },
    { 'n', '<leader>ttq' }, { 'n', 'gI' }, { 'n', '<leader>D' }, { 'i', '<C-h>' } }) do
    if has_key(k[1], k[2]) then bad[#bad + 1] = k[1] .. ' ' .. k[2] end
  end
  return #bad == 0, 'still defined: ' .. table.concat(bad, ', ')
end)

-- Problems: see them, move between them, fix them -- obvious keys, no jargon.
check.global('problems_keys', function()
  local bad = {}
  for _, lhs in ipairs({ '<leader>ee', '<leader>ea', '<leader>ef', '<leader>en', '<leader>ep' }) do
    if not has_key('n', lhs) then bad[#bad + 1] = lhs .. ' missing' end
  end
  -- jumping to a problem shows its message in a popup (built-in ]d too)
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(fixtures .. '/lua/init.lua')
  local ns = vim.api.nvim_create_namespace('czcheck_prob')
  vim.diagnostic.set(ns, 0, { { lnum = 4, col = 0, message = 'injected problem', severity = vim.diagnostic.severity.ERROR } })
  for _, keys in ipairs({ '<leader>en', ']d' }) do
    vim.cmd('silent! only'); vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local wins = #vim.api.nvim_list_wins()
    vim.api.nvim_feedkeys(vim.keycode(keys), 'x', false)
    vim.wait(300)
    if vim.api.nvim_win_get_cursor(0)[1] ~= 5 or #vim.api.nvim_list_wins() <= wins then bad[#bad + 1] = keys .. ' did not jump and show the message' end
  end
  vim.diagnostic.reset(ns, 0); vim.cmd('silent! only')
  return #bad == 0, table.concat(bad, ', ')
end)

check.global('find_helper_keys', function()
  local bad = {}
  for _, lhs in ipairs({ '<leader>pk', '<leader>pr', '<leader>pw' }) do
    if not has_key('n', lhs) then bad[#bad + 1] = lhs .. ' missing' end
  end
  return #bad == 0, table.concat(bad, ', ')
end)

-- :checkhealth czernous lists the system tools the config relies on, so a new
-- machine can be checked at a glance.
check.global('health_lists_tools', function()
  -- a PATH without ripgrep (but with everything else)
  local dirs = vim.tbl_filter(function(d) return vim.fn.executable(d .. '/rg') == 0 end, vim.split(vim.env.PATH, ':', { plain = true }))
  local out = vim.system({ vim.v.progpath, '--headless', '-n', '-c', 'checkhealth czernous',
    '-c', "lua io.stdout:write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'))", '-c', 'qa!' },
    { text = true, cwd = root, env = { PATH = table.concat(dirs, ':') } }):wait(40000)
  local text = (out.stdout or '') .. (out.stderr or '')
  -- servers installed through Mason must be reported as found even this early after startup
  local mason_ok = vim.fn.executable(vim.fn.stdpath('data') .. '/mason/bin/lua-language-server') == 0 or text:find('OK[^\n]*lua%-language%-server')
  local ok = text:find('ERROR[^\n]*ripgrep') and text:find('OK[^\n]*git') and mason_ok and not text:find('stack traceback')
  return ok ~= nil, text:gsub('\n', ' | '):sub(1, 300)
end)

---------------------------------------------------------------------------
-- Review fixes (stage 2a part 2)
---------------------------------------------------------------------------
-- <leader>f must not search $PATH on every press (each miss ~100 ms on slow PATHs):
-- programs are located once, in the background, and remembered.
check.global('format_does_not_search_path', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'x = 1' }, dir .. '/f.py')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/f.py')
  local fmt = require('czernous.format')
  local function searches()
    local n = 0
    for name, count in pairs(check.exe_calls) do if name:sub(1, 1) ~= '/' then n = n + count end end
    return n
  end
  count_warnings(function() fmt.format(); vim.wait(2500) end) -- first press: background lookup
  local before = searches()
  local t0 = vim.uv.hrtime()
  count_warnings(function() fmt.format() end)                 -- later presses: nothing to look up
  local blocked_ms = (vim.uv.hrtime() - t0) / 1e6
  vim.wait(300)
  return searches() == before and blocked_ms < 30, ('PATH searches on a repeat press: %d; blocked for %.0f ms'):format(searches() - before, blocked_ms)
end)

check.global('clipboard_fallback_enabled', function()
  local disabled = require('lazy.core.config').options.performance.rtp.disabled_plugins
  return not vim.tbl_contains(disabled, 'osc52'), 'the built-in OSC 52 clipboard (copy through the terminal, no tool needed) is disabled'
end)

check.global('statusline_does_not_load_diagnostics_at_startup', function()
  local r = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua io.stdout:write('DIAG=' .. tostring(package.loaded['vim.diagnostic'] ~= nil) .. ' STL=' .. tostring(vim.o.statusline ~= '')) vim.cmd('qa!')" },
    { text = true, cwd = root }):wait(30000)
  local out = (r.stdout or '') .. (r.stderr or '')
  return out:find('DIAG=false STL=true') ~= nil, out:sub(1, 120)
end)

-- A theme that fails to load (plugin missing after an offline first start) must
-- not take the rest of the config down with it.
check.global('theme_failure_does_not_stop_startup', function()
  local cache = vim.fn.tempname(); vim.fn.mkdir(cache, 'p') -- empty: the theme has to be built
  local r = vim.system({ vim.v.progpath, '--headless', '-n',
    '--cmd', "lua package.preload['catppuccin'] = function() error('simulated: theme plugin missing') end",
    '--cmd', "autocmd VimEnter * ++once lua vim.defer_fn(function() io.stdout:write(('ALIVE stl=%s start=%s lsp=%s'):format(tostring(vim.o.statusline ~= ''), tostring(vim.b.czernous_start == true), tostring(package.loaded['czernous.lsp'] ~= nil))) vim.cmd('qa!') end, 400)" },
    { text = true, cwd = root, env = { XDG_CACHE_HOME = cache } }):wait(30000)
  local out = (r.stdout or '') .. (r.stderr or '')
  return out:find('ALIVE stl=true start=true lsp=true') ~= nil, out:gsub('\n', ' | '):sub(1, 260)
end)

check.global('start_screen_respects_what_was_asked_for', function()
  -- `nvim <folder> +Oil`: the explorer the user asked for stays
  local r = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua vim.defer_fn(function() io.stdout:write('FT=' .. vim.bo.filetype .. ' START=' .. tostring(vim.b.czernous_start == true) .. ' TS=' .. tostring(package.loaded['nvim-treesitter'] ~= nil)) vim.cmd('qa!') end, 600)",
    '.', '+Oil' }, { text = true, cwd = root }):wait(30000)
  local with_oil = (r.stdout or '') .. (r.stderr or '')
  -- plain `nvim .`: start screen, and it does not drag syntax-highlighting plugins in
  local r2 = vim.system({ vim.v.progpath, '--headless', '-n', '--cmd',
    "autocmd VimEnter * ++once lua vim.defer_fn(function() io.stdout:write('FT=' .. vim.bo.filetype .. ' START=' .. tostring(vim.b.czernous_start == true) .. ' TS=' .. tostring(package.loaded['nvim-treesitter'] ~= nil)) vim.cmd('qa!') end, 600)",
    '.' }, { text = true, cwd = root }):wait(30000)
  local plain = (r2.stdout or '') .. (r2.stderr or '')
  local ok = with_oil:find('FT=oil START=false') and plain:find('START=true TS=false')
  return ok ~= nil, ('nvim . +Oil -> %s || nvim . -> %s'):format(with_oil:sub(1, 60), plain:sub(1, 60))
end)

check.global('hover_says_starting_not_missing', function()
  -- a server that is enabled for the filetype but not attached yet: "still starting", not "install one"
  local lsp = require('czernous.lsp')
  if not lsp.describe_missing then return false, 'lsp.describe_missing missing' end
  local starting = lsp.describe_missing('lua', true)
  local missing = lsp.describe_missing('kotlin', false)
  return starting:lower():find('starting', 1, true) ~= nil and missing:lower():find('no language server', 1, true) ~= nil,
    ('starting -> %q; missing -> %q'):format(starting:sub(1, 60), missing:sub(1, 60))
end)

check.global('no_cfg_dir', function()
  return vim.fn.isdirectory(root .. '/lua/czernous/cfg') == 0, 'lua/czernous/cfg still exists'
end)

-- Loading a plugin spec file must only return a spec, not create keymaps.
check.global('plugin_specs_have_no_side_effects', function()
  local bad = {}
  for _, f in ipairs(vim.fn.glob(root .. '/lua/czernous/plugins/*.lua', false, true)) do
    local before = #check.recorded
    local ok, ret = pcall(dofile, f)
    local calls = #check.recorded - before
    if not ok or type(ret) ~= 'table' or calls > 0 then
      bad[#bad + 1] = vim.fn.fnamemodify(f, ':t') .. (calls > 0 and (' (sets ' .. calls .. ' keymaps)') or ' (no spec table)')
    end
    -- forget the re-recorded maps so other checks don't see them twice
    for _ = 1, calls do table.remove(check.recorded) end
  end
  return #bad == 0, table.concat(bad, ', ')
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

  -- CHECK_ONLY=<lua patterns separated by |>: run only the matching global checks
  -- (fast; used by --tripwires). Language checks are skipped then.
  local only = vim.env.CHECK_ONLY
  if only == '' then only = nil end
  local function wanted(name)
    if not only then return true end
    for pat in only:gmatch('[^|]+') do if name:match(pat) then return true end end
    return false
  end
  local function run_global(g)
    local ok, passed, msg = pcall(g.fn)
    if not ok then report('FAIL', g.name, passed)
    elseif passed == 'skip' then report('SKIP', g.name, msg)
    elseif passed then report('PASS', g.name)
    else report('FAIL', g.name, msg) end
  end

  for _, g in ipairs(check.globals) do
    if g.early and wanted(g.name) then run_global(g) end
  end
  if not only then
    for _, spec in ipairs(check.langs) do
      local ok, err = pcall(run_lang, spec)
      if not ok then report('FAIL', 'lang:' .. spec.name, err) end
    end
  end
  for _, g in ipairs(check.globals) do
    if not g.early and not g.late and wanted(g.name) then run_global(g) end
  end
  for _, g in ipairs(check.globals) do
    if g.late and wanted(g.name) then run_global(g) end
  end

  -- Errors last, so everything above had a chance to produce them.
  check.snapshot_messages()
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
