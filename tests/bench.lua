-- Benchmarks for this config. Run via ./tests/bench.sh (see its header).
--
-- "Measure, then say the number": every timing is reported as min / median / max
-- of N runs, from two whole passes. A measure is only quotable when the FASTEST
-- run of both passes agrees within 15% (on a shared machine noise only adds time,
-- so the minimum is the repeatable figure; medians and maxima show the spread and
-- may differ more). A measure that failed in either pass is never "stable".
-- Allocation per event is the exact instrument for hot paths (bytes of Lua
-- memory per autocmd firing, GC stopped).
--
-- This file is both the driver (`nvim -u NONE -l tests/bench.lua ...`) and the
-- probe loaded inside each child Neovim (`--cmd "luafile tests/bench.lua"` with
-- $BENCH_PROBE set).

local M = {}
local uv = vim.uv
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixtures = root .. '/tests/fixtures'

local TOLERANCE = 0.15

local function stats(samples)
  table.sort(samples)
  local n = #samples
  if n == 0 then return nil end
  local median = n % 2 == 1 and samples[(n + 1) / 2] or (samples[n / 2] + samples[n / 2 + 1]) / 2
  return { median = median, min = samples[1], max = samples[n], n = n }
end

--- True when every figure present in both results agrees within TOLERANCE;
--- otherwise false plus a list of what disagreed.
function M.compare(a, b)
  local bad = {}
  local function walk(x, y, path)
    if type(x) ~= 'table' then return end
    -- A measure that errored or is missing in either pass has no evidence behind it.
    if x.error or (type(y) == 'table' and y.error) then
      bad[#bad + 1] = ('%s: failed (%s)'):format(path, tostring(x.error or y.error))
      return
    end
    if x.median and (type(y) ~= 'table' or not y.median) then
      bad[#bad + 1] = path .. ': missing in one pass'
      return
    end
    if type(y) ~= 'table' then return end
    if x.median and y.median then
      -- Timings: compare the fastest run. On a shared machine noise only ever adds
      -- time, so the minimum is the repeatable figure; medians are reported too.
      local xv, yv = x.min or x.median, y.min or y.median
      local hi, lo = math.max(xv, yv), math.min(xv, yv)
      -- tiny values: absolute slack (1 ms / 1 byte); ratios are meaningless there
      if hi - lo > 1 and (hi - lo) / hi > TOLERANCE then
        bad[#bad + 1] = ('%s: %.1f vs %.1f'):format(path, xv, yv)
      end
      return
    end
    for k, v in pairs(x) do walk(v, y[k], path == '' and tostring(k) or (path .. '.' .. tostring(k))) end
  end
  walk(a, b, '')
  walk(b, a, '') -- and the other way round, for measures only the second pass has
  return #bad == 0, bad
end

---------------------------------------------------------------------------
-- Probes (run inside a child Neovim that loaded the config under test)
---------------------------------------------------------------------------
local function emit(tbl) io.stdout:write('BENCH ' .. vim.json.encode(tbl) .. '\n') end

local probes = {}

-- Time from process start (this --cmd) until treesitter highlighting is active.
function probes.open(t0)
  local buf = vim.api.nvim_get_current_buf()
  local timer = uv.new_timer()
  timer:start(0, 1, vim.schedule_wrap(function()
    if vim.treesitter.highlighter.active[buf] then
      timer:stop(); timer:close()
      emit({ ms = (uv.hrtime() - t0) / 1e6 })
      vim.cmd('qa!')
    elseif (uv.hrtime() - t0) / 1e9 > 20 then
      timer:stop(); timer:close()
      emit({ error = 'no highlighter after 20s' })
      vim.cmd('qa!')
    end
  end))
end

-- Bytes of Lua memory allocated per event on the hot paths.
function probes.alloc()
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(8000, function() return #vim.lsp.get_clients({ bufnr = buf }) > 0 end, 100)
  vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy', modeline = false })
  vim.wait(500)
  local N = 1000
  local function measure(fn)
    for _ = 1, 50 do fn() end -- warm up (JIT, caches)
    collectgarbage('collect'); collectgarbage('collect'); collectgarbage('stop')
    local before = collectgarbage('count')
    for _ = 1, N do fn() end
    local bytes = (collectgarbage('count') - before) * 1024 / N
    collectgarbage('restart')
    return bytes
  end
  local out = {}
  for _, ev in ipairs({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'InsertCharPre', 'BufEnter', 'WinScrolled' }) do
    out[ev] = measure(function() vim.api.nvim_exec_autocmds(ev, { buffer = buf, modeline = false }) end)
  end
  local stl = vim.o.statusline
  out.statusline = measure(function() vim.api.nvim_eval_statusline(stl, {}) end)
  emit({ bytes = out })
  vim.cmd('qa!')
end

if vim.env.BENCH_PROBE then
  local t0 = uv.hrtime()
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function() vim.schedule(function() probes[vim.env.BENCH_PROBE](t0) end) end,
  })
  return M
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
--- Milliseconds from spawning Neovim until it reports it is ready (VimEnter):
--- what you wait for when you open the editor. Shutdown is not included (unlike
--- timing `nvim +qa`, which also pays for writing ShaDa on exit).
function M.ready_ms(args, env, cwd)
  local t0, t1 = uv.hrtime(), nil
  local cmd = { vim.v.progpath, '--headless', '--cmd',
    "autocmd VimEnter * ++once lua io.stdout:write('R') io.stdout:flush() vim.cmd('qa!')" }
  vim.list_extend(cmd, args or {})
  vim.system(cmd, { env = env, cwd = cwd or root, stdout = function(_, data)
    if data and not t1 then t1 = uv.hrtime() end
  end }):wait(60000)
  return t1 and (t1 - t0) / 1e6 or nil
end

local function child(args, env, timeout)
  local cmd = vim.list_extend({ vim.v.progpath, '--headless' }, args)
  local r = vim.system(cmd, { text = true, env = env, cwd = root }):wait(timeout or 120000)
  for line in ((r.stdout or '') .. '\n' .. (r.stderr or '')):gmatch('[^\n]+') do
    local json = line:match('BENCH (%b{})')
    if json then return vim.json.decode(json) end
  end
  return { error = 'no result (exit ' .. tostring(r.code) .. ')' }
end

local LANGS = {
  go = 'go/main.go', rust = 'rust/src/main.rs', csharp = 'csharp/Program.cs',
  ts = 'ts/index.ts', java = 'java/src/Main.java', lua = 'lua/init.lua',
}
-- `open` = keys that start a new line where completion makes sense (inside main for Go).
local COMPLETION = {
  lua = { file = 'lua/init.lua', prefix = 'pri', open = '<Esc>Go' },
  go = { file = 'go/main.go', prefix = 'fmt.Pr', open = '<Esc>10GO' },
}

-- Lua run inside the child: is a completion menu showing WITH language-server
-- items in it? (Snippet and path suggestions are local and appear instantly;
-- timing those would flatter any engine. What matters is the server's answer.)
local VISIBLE = [[
  local cmp = package.loaded['cmp']
  if cmp and cmp.visible then
    if not cmp.visible() then return false end
    for _, e in ipairs(cmp.get_entries()) do if e.source.name == 'nvim_lsp' then return true end end
    return false
  end
  local blink = package.loaded['blink.cmp']
  if blink and blink.is_menu_visible then
    if not blink.is_menu_visible() then return false end
    local list = package.loaded['blink.cmp.completion.list']
    for _, item in ipairs(list and list.items or {}) do if item.source_id == 'lsp' then return true end end
    return false
  end
  return vim.fn.pumvisible() == 1
]]

--- Last keystroke -> completion menu visible. The child runs in a pseudo-terminal
--- (completion engines don't auto-trigger without a UI) and is driven over a
--- socket; the prefix is typed one key at a time, like a person would.
function M.completion(file, prefix, open, runs, env, accept)
  local sock = vim.fn.tempname() .. '.sock'
  local job = vim.fn.jobstart({ vim.v.progpath, '-n', '--listen', sock, file }, {
    pty = true, width = 120, height = 40, cwd = root, on_stdout = function() end,
    env = vim.tbl_extend('force', { TERM = 'xterm-256color' }, env or {}),
  })
  local function done(result) pcall(vim.fn.jobstop, job); return result end
  if not vim.wait(5000, function() return uv.fs_stat(sock) ~= nil end, 20) then return done({ error = 'child did not start' }) end
  local ch = vim.fn.sockconnect('pipe', sock, { rpc = true })
  local function lua(code) return vim.rpcrequest(ch, 'nvim_exec_lua', code, {}) end
  local function poll(ms, code)
    local t0 = uv.hrtime()
    while (uv.hrtime() - t0) / 1e6 < ms do
      local ok, v = pcall(lua, code)
      if ok and v then return (uv.hrtime() - t0) / 1e6 end
      vim.wait(1)
    end
  end
  local ready = [[local c = vim.lsp.get_clients({ bufnr = 0 })[1]
    return (c and c.initialized and c:supports_method('textDocument/completion', 0)) or false]]
  if not poll(60000, ready) then return done({ error = 'no LSP completion provider attached' }) end
  vim.wait(2000)
  local samples, attempts = {}, 0
  while #samples < runs + 2 and attempts < runs * 3 do
    attempts = attempts + 1
    vim.rpcrequest(ch, 'nvim_input', open)
    for i = 1, #prefix - 1 do
      vim.rpcrequest(ch, 'nvim_input', prefix:sub(i, i)); vim.wait(40)
    end
    vim.rpcrequest(ch, 'nvim_input', '<Esc>a') -- close any menu from earlier keys; time only the last key
    vim.wait(60)
    vim.rpcrequest(ch, 'nvim_input', prefix:sub(-1))
    local ms = poll(5000, VISIBLE)
    if ms then samples[#samples + 1] = ms end
    vim.rpcrequest(ch, 'nvim_input', '<Esc>u')
    vim.wait(200)
  end
  local accepted
  if accept then
    vim.rpcrequest(ch, 'nvim_input', open)
    for i = 1, #prefix do vim.rpcrequest(ch, 'nvim_input', prefix:sub(i, i)); vim.wait(60) end
    if poll(5000, VISIBLE) then
      vim.wait(150)
      vim.rpcrequest(ch, 'nvim_input', '<CR>')
      vim.wait(300)
      accepted = lua('return vim.api.nvim_get_current_line()')
    end
    vim.rpcrequest(ch, 'nvim_input', '<Esc>u')
  end
  pcall(vim.rpcrequest, ch, 'nvim_command', 'qa!')
  if accept then
    local st = #samples >= 3 and stats(samples) or { error = 'menu never appeared' }
    st.accepted = accepted
    return done(st)
  end
  if #samples < 3 then return done({ error = 'menu never appeared' }) end
  table.remove(samples, 1); table.remove(samples, 1) -- warm-up
  return done(stats(samples))
end

local function pass(runs, env)
  local probe = '--cmd'
  local load = 'luafile ' .. root .. '/tests/bench.lua'
  local function with(extra) return vim.tbl_extend('force', env or {}, extra) end
  local res = { open_ms = {}, completion_ms = {}, alloc_bytes_per_event = {} }

  local s = {}
  for _ = 1, runs do
    local f = vim.fn.tempname()
    vim.system({ vim.v.progpath, '--headless', '--startuptime', f, '+qa' }, { env = env, cwd = root }):wait(60000)
    for line in io.lines(f) do
      local t = line:match('^(%d+%.%d+).*NVIM STARTED')
      if t then s[#s + 1] = tonumber(t) end
    end
    os.remove(f)
  end
  res.startup_ms = stats(s)

  for lang, file in pairs(LANGS) do
    local o = {}
    for _ = 1, runs do
      local r = child({ probe, load, fixtures .. '/' .. file }, with({ BENCH_PROBE = 'open' }), 40000)
      if r.ms then o[#o + 1] = r.ms end
      vim.wait(400) -- let the language server from this run exit before the next one
    end
    res.open_ms[lang] = stats(o) or { error = 'no samples' }
  end

  for lang, c in pairs(COMPLETION) do
    res.completion_ms[lang] = M.completion(fixtures .. '/' .. c.file, c.prefix, c.open, runs, env)
  end

  -- Wall-clock launch (what you feel) and the floor: the same Neovim with no config.
  local function launch(args)
    local t = {}
    for _ = 1, runs do
      local t0 = uv.hrtime()
      vim.system(vim.list_extend({ vim.v.progpath, '--headless' }, args), { env = env, cwd = root }):wait(60000)
      t[#t + 1] = (uv.hrtime() - t0) / 1e6
    end
    return stats(t)
  end
  res.launch_ms = launch({ '+qa' })
  res.bare_launch_ms = launch({ '-u', 'NONE', '+qa' })
  -- The headline: spawn -> ready, without shutdown.
  local function ready(args)
    local t = {}
    for _ = 1, runs do t[#t + 1] = M.ready_ms(args, env) end
    return stats(t)
  end
  res.ready_ms = ready({})
  res.bare_ready_ms = ready({ '-u', 'NONE' })

  local a = child({ probe, load, fixtures .. '/lua/init.lua' }, with({ BENCH_PROBE = 'alloc' }), 60000)
  for ev, bytes in pairs(a.bytes or {}) do
    res.alloc_bytes_per_event[ev] = { median = math.floor(bytes + 0.5) }
  end
  if a.error then res.alloc_bytes_per_event.error = a.error end
  return res
end

function M.main(argv)
  local runs, label, xdg = 10, 'run', nil
  local i = 1
  while i <= #argv do
    if argv[i] == '--runs' then runs = tonumber(argv[i + 1]); i = i + 1
    elseif argv[i] == '--label' then label = argv[i + 1]; i = i + 1
    elseif argv[i] == '--config' then xdg = argv[i + 1]; i = i + 1 end
    i = i + 1
  end
  local env
  if xdg then
    env = {
      XDG_CONFIG_HOME = xdg .. '/config', XDG_DATA_HOME = xdg .. '/data',
      XDG_STATE_HOME = xdg .. '/state', XDG_CACHE_HOME = xdg .. '/cache',
    }
  end
  local first = pass(runs, env)
  local second = pass(runs, env)
  local stable, disagreements = M.compare(first, second)
  second.stable, second.disagreements = stable, disagreements
  second.first_pass = first
  second.runs = runs
  second.nvim = tostring(vim.version())
  local out = root .. '/tests/bench/' .. label .. '.json'
  vim.fn.mkdir(root .. '/tests/bench', 'p')
  vim.fn.writefile({ vim.json.encode(second) }, out)
  local function row(name, v)
    if v.error then return ('%-28s %s'):format(name, v.error) end
    if v.min then return ('%-28s min %7.1f  median %7.1f  max %7.1f  (n=%d)'):format(name, v.min, v.median, v.max, v.n) end
    return ('%-28s %8d'):format(name, v.median)
  end
  print(row('READY (spawn -> usable) ms', second.ready_ms))
  print(row('bare nvim ready ms', second.bare_ready_ms))
  print(row('launch+quit (nvim +qa) ms', second.launch_ms))
  print(row('bare launch+quit ms', second.bare_launch_ms))
  print(row('startup (internal) ms', second.startup_ms))
  for k, v in vim.spairs(second.open_ms) do print(row('open ' .. k .. ' ms', v)) end
  for k, v in vim.spairs(second.completion_ms) do print(row('completion ' .. k .. ' ms', v)) end
  for k, v in vim.spairs(second.alloc_bytes_per_event) do
    if type(v) == 'table' then print(row('alloc ' .. k .. ' B/event', v)) end
  end
  print(second.stable and 'STABLE: two passes agree within 15% on every measure'
    or ('UNSTABLE (do not quote these; the rest agree within 15%): ' .. table.concat(disagreements, '; ')))
  print('wrote ' .. out)
end

if _G.arg and _G.arg[0] and _G.arg[0]:match('bench%.lua$') then
  M.main(_G.arg)
end

return M
