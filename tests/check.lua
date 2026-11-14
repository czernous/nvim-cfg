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
---@param opts? { early?: boolean } early = run before the language checks, while the
---   machine is still quiet (timing checks: language servers started later skew them)
function check.global(name, fn, opts)
  table.insert(check.globals, { name = name, fn = fn, early = opts and opts.early or false })
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
  local lcfg = require('lualine').get_config()
  local has = false
  for _, sec in pairs(lcfg.sections) do
    for _, comp in ipairs(sec) do if comp == 'diagnostics' or (type(comp) == 'table' and comp[1] == 'diagnostics') then has = true end end
  end
  if not has then return false, 'lualine has no diagnostics component' end
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

-- <leader>f: project's Spotless if present, else LSP, else Neoformat.
check.global('format_falls_back', function()
  local ok, fmt = pcall(require, 'czernous.format')
  if not ok or not fmt.format then return false, 'czernous.format.format missing' end
  vim.cmd('silent! %bwipeout!'); vim.cmd('enew'); vim.bo.filetype = 'text'
  local called = false
  vim.api.nvim_create_user_command('Neoformat', function() called = true end, { force = true })
  fmt.format()
  return called, 'Neoformat not called in a buffer without LSP'
end)

-- Fake Gradle project whose ./gradlew behaves like the Spotless IDE hook.
local function fake_spotless_project(script)
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile({ 'plugins { id("com.diffplug.spotless") }' }, dir .. '/build.gradle.kts')
  vim.fn.writefile(script, dir .. '/gradlew'); vim.fn.setfperm(dir .. '/gradlew', 'rwxr-xr-x')
  vim.fn.writefile({ 'hello', 'world' }, dir .. '/src/x.txt')
  return dir
end

check.global('format_uses_spotless', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'echo "IS DIRTY" >&2', 'tr a-z A-Z' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  require('czernous.format').format()
  vim.wait(5000, function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO' end, 50)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return vim.deep_equal(lines, { 'HELLO', 'WORLD' }), vim.inspect(lines)
end)

check.global('format_spotless_clean_is_noop', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'cat >/dev/null', 'echo "IS CLEAN" >&2' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  require('czernous.format').format()
  vim.wait(1500)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return vim.deep_equal(lines, { 'hello', 'world' }) and not vim.bo.modified, vim.inspect(lines)
end)

check.global('format_spotless_failure_warns', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'cat >/dev/null', 'echo "BUILD FAILED" >&2', 'exit 1' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  local before, warned = #check.errors, false
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warned = true end return n(m, l, o) end
  require('czernous.format').format()
  vim.wait(3000, function() return warned end, 50)
  vim.notify = n
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return warned and #check.errors == before and vim.deep_equal(lines, { 'hello', 'world' }),
    ('warned=%s errors=%d lines=%s'):format(warned, #check.errors - before, vim.inspect(lines))
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

-- Theme: one spot; transparent editor background that survives theme changes.
local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end

check.global('transparent_normal', function()
  local ok, theme = pcall(require, 'czernous.theme')
  if not ok or type(theme) ~= 'table' or not theme.opts then return false, 'czernous.theme has no opts' end
  if not theme.opts.transparent then return false, 'transparent is off by default' end
  local n = hl('Normal')
  return n.bg == nil and n.fg ~= nil, ('Normal bg=%s fg=%s'):format(tostring(n.bg), tostring(n.fg))
end)

check.global('floats_keep_bg', function()
  local bad = {}
  for _, g in ipairs({ 'NormalFloat', 'Pmenu' }) do if hl(g).bg == nil then bad[#bad + 1] = g end end
  return #bad == 0, 'no background: ' .. table.concat(bad, ', ')
end)

check.global('survives_colorscheme_change', function()
  local theme = require('czernous.theme')
  vim.cmd.colorscheme('catppuccin')
  local bg = hl('Normal').bg
  vim.cmd.colorscheme(theme.opts.colorscheme)
  return bg == nil, 'catppuccin Normal bg=' .. tostring(bg)
end)

check.global('toggle_restores_bg', function()
  local theme = require('czernous.theme')
  if not theme.toggle_transparency then return false, 'toggle_transparency missing' end
  theme.toggle_transparency()
  local opaque = hl('Normal').bg
  theme.toggle_transparency()
  local again = hl('Normal').bg
  return opaque ~= nil and again == nil, ('after toggle bg=%s, after 2nd toggle bg=%s'):format(tostring(opaque), tostring(again))
end)

check.global('special_buffers_are_quiet', function()
  local before = #check.errors
  for _, cmd in ipairs({ 'help help', 'Ex', 'terminal', 'enew' }) do
    vim.cmd('silent! %bwipeout!')
    local ok, err = pcall(vim.cmd, cmd)
    if not ok then return false, cmd .. ': ' .. tostring(err) end
    vim.wait(300)
  end
  return #check.errors == before, table.concat(check.errors, ' | ')
end)

check.global('format_spotless_uncovered_falls_back', function()
  -- Hook exits 0 with no IS DIRTY/IS CLEAN = file not in any Spotless target.
  local dir = fake_spotless_project({ '#!/bin/sh', 'cat >/dev/null', 'exit 0' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  local called, warned = false, false
  vim.api.nvim_create_user_command('Neoformat', function() called = true end, { force = true })
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN then warned = true end return n(m, l, o) end
  require('czernous.format').format()
  vim.wait(3000, function() return called end, 50)
  vim.notify = n
  return called and not warned, ('fell back=%s warned=%s'):format(called, warned)
end)

check.global('format_spotless_empty_output_keeps_buffer', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'cat >/dev/null', 'echo "IS DIRTY" >&2' })
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  require('czernous.format').format()
  vim.wait(1500)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return vim.deep_equal(lines, { 'hello', 'world' }), vim.inspect(lines)
end)

check.global('format_spotless_skips_unnamed_buffers', function()
  local dir = fake_spotless_project({ '#!/bin/sh', 'touch "$0.ran"', 'cat >/dev/null', 'echo "IS CLEAN" >&2' })
  local cwd = vim.fn.getcwd()
  vim.cmd('silent! %bwipeout!'); vim.cmd.cd(dir); vim.cmd('enew')
  local called = false
  vim.api.nvim_create_user_command('Neoformat', function() called = true end, { force = true })
  require('czernous.format').format()
  vim.wait(1000)
  vim.cmd.cd(cwd)
  local ran = vim.fn.filereadable(dir .. '/gradlew.ran') == 1
  return called and not ran, ('fallback=%s gradlew ran=%s'):format(called, ran)
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
end)

check.global('no_global_writes', function()
  local bad = {}
  for _, g in ipairs(check.global_writes) do bad[#bad + 1] = g.name .. ' at ' .. g.src end
  vim.list_extend(bad, scan({ '_G%.[%w_]+%s*=', '_G%[' }))
  return #bad == 0, table.concat(bad, ', ')
end)

-- "Reflection": code that inspects or builds code at runtime.
check.global('no_reflection', function()
  local bad = scan({ 'debug%.', 'loadstring', '[^%w_]load%(', 'setfenv', 'getfenv' })
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
check.global('lualine_follows_theme', function()
  local theme = require('lualine').get_config().options.theme
  return theme == 'auto', 'lualine theme = ' .. vim.inspect(theme)
end)

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

check.global('spotless_in_subproject_detected', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir .. '/mod/src', 'p')
  vim.fn.writefile({ 'plugins { java }' }, dir .. '/build.gradle.kts')
  vim.fn.writefile({ 'plugins { id("com.diffplug.spotless") }' }, dir .. '/mod/build.gradle.kts')
  vim.fn.writefile({ '#!/bin/sh', 'echo "IS DIRTY" >&2', 'tr a-z A-Z' }, dir .. '/gradlew'); vim.fn.setfperm(dir .. '/gradlew', 'rwxr-xr-x')
  vim.fn.writefile({ 'hello' }, dir .. '/mod/src/x.txt')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/mod/src/x.txt')
  require('czernous.format').format()
  vim.wait(5000, function() return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO' end, 50)
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'HELLO', 'Spotless in a subproject build file was not used'
end)

check.global('spotless_gradlew_not_executable_warns', function()
  local dir = vim.fn.tempname(); vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile({ 'plugins { id("com.diffplug.spotless") }' }, dir .. '/build.gradle.kts')
  vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, dir .. '/gradlew'); vim.fn.setfperm(dir .. '/gradlew', 'rw-r--r--')
  vim.fn.writefile({ 'hello' }, dir .. '/src/x.txt')
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/src/x.txt')
  local before, warned, fell_back = #check.errors, false, false
  vim.api.nvim_create_user_command('Neoformat', function() fell_back = true end, { force = true })
  local n = vim.notify
  vim.notify = function(m, l, o) if l == vim.log.levels.WARN and tostring(m):find('gradlew') then warned = true end return n(m, l, o) end
  local ok, err = pcall(require('czernous.format').format)
  vim.wait(1500, function() return fell_back end, 50)
  vim.notify = n
  return ok and warned and fell_back and #check.errors == before,
    ('ok=%s warned=%s fell back=%s errors=%d %s'):format(tostring(ok), tostring(warned), tostring(fell_back), #check.errors - before, tostring(err or ''))
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
  local theme = require('czernous.theme').plugin or 'onedark'
  local extra = {}
  for name in loaded:gmatch('[^,]+') do
    if name ~= 'lazy.nvim' and name ~= theme then extra[#extra + 1] = name end
  end
  return #extra == 0, ('loaded before the first screen: %s%s'):format(table.concat(extra, ', '), trip and ' [tripwire eager active]' or '')
end)

-- Generous ceiling (target is ~5 ms over bare Neovim): catches a regression like
-- the 1 s one found in step 1 without failing on a noisy machine.
check.global('launch_within_budget', function()
  local bench = dofile(root .. '/tests/bench.lua')
  local function fastest(args)
    local best = math.huge
    for _ = 1, 9 do best = math.min(best, bench.ready_ms(args) or math.huge) end
    return best
  end
  -- spawn -> ready (shutdown excluded), config vs bare Neovim
  local bare, config = fastest({ '-u', 'NONE' }), fastest({})
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
    if not g.early and wanted(g.name) then run_global(g) end
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
