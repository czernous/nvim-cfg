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

check.startup_lookups = {}
check.exe_calls = {}
local orig_executable = vim.fn.executable
vim.fn.executable = function(name)
  if vim.v.vim_did_enter == 0 then table.insert(check.startup_lookups, name) end
  check.exe_calls[name] = (check.exe_calls[name] or 0) + 1
  return orig_executable(name)
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
  if vim.fn.executable('lua-language-server') == 0 then return true end
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
  vim.wait(5000)
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
  if not reg.which_key then return false, 'keymaps.which_key() missing' end
  local all = reg.all()
  local bad = {}
  for _, g in ipairs(reg.which_key()) do
    local used = false
    for _, k in ipairs(all) do
      if k.lhs ~= g[1] and k.lhs:sub(1, #g[1]) == g[1] then used = true end
    end
    if not used then bad[#bad + 1] = g[1] .. ' (' .. g.group .. ')' end
  end
  return #bad == 0, 'groups with no keys: ' .. table.concat(bad, ', ')
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
