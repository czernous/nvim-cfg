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

check.global('enabled_matches_path', function()
  local ok, lsp = pcall(require, 'czernous.lsp')
  if not ok or type(lsp) ~= 'table' or not lsp.servers or not lsp.enabled then return false, 'czernous.lsp has no servers/enabled' end
  local want, got = {}, {}
  for name, exe in pairs(lsp.servers) do
    if vim.fn.executable(exe) == 1 then want[#want + 1] = name end
  end
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
  vim.cmd('silent! %bwipeout!'); vim.cmd.edit(dir .. '/x.czfake'); vim.bo.filetype = 'czfake'
  vim.wait(3000)
  vim.lsp.enable('fake_ls', false)
  vim.notify = n; vim.env.PATH = old
  local msgs = vim.api.nvim_exec2('messages', { output = true }).output
  local errs = #check.errors - before
  for line in msgs:gmatch('[^\n]+') do if line:match('^E%d+:') or line:match('^Error') then errs = errs + 1 end end
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

-- <leader>f: LSP formatting if a server can, otherwise Neoformat.
check.global('format_falls_back', function()
  local ok, lsp = pcall(require, 'czernous.lsp')
  if not ok or not lsp.format then return false, 'czernous.lsp.format missing' end
  vim.cmd('silent! %bwipeout!'); vim.cmd('enew'); vim.bo.filetype = 'text'
  local called = false
  vim.api.nvim_create_user_command('Neoformat', function() called = true end, { force = true })
  lsp.format()
  return called, 'Neoformat not called in a buffer without LSP'
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
