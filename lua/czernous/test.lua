-- Running tests. Keys: <leader>r...
--
--   <leader>rt  the test the cursor is in      <leader>rf  this file's tests
--   <leader>ra  all the project's tests        <leader>rl  the last run again
--
-- No plugin: the project's own test command is built for the file's language
-- and run in a floating terminal, so you see exactly what the tool prints.
-- In that window: `q` closes it, Enter on a `file:line` jumps there.
--
--   Go          go test                  Rust   cargo test
--   Java/Kotlin ./gradlew test (or mvn)  C#     dotnet test
--   JS / TS     bun test (bun.lock), else the project's vitest or jest
--
-- The file is saved first (tests run what is on disk). A missing program gives
-- one message that names it.

local M = {}

--- The last thing run: { cmd = { program, args... }, cwd = folder }.
M.last = nil

--- Nearest folder at or above `from` that contains one of `names` (plain names
--- or Lua patterns), or nil.
local function folder_with(from, names, patterns)
  local found = vim.fs.find(function(name)
    if vim.tbl_contains(names, name) then return true end
    for _, pattern in ipairs(patterns or {}) do
      if name:match(pattern) then return true end
    end
    return false
  end, { upward = true, path = from, limit = 1 })[1]
  return found and vim.fs.dirname(found) or nil
end

--- The syntax-tree node of one of `types` that the cursor is inside, or nil.
local function enclosing(types)
  -- make sure the file has been parsed (highlighting may not have got to it yet)
  local has_parser, parser = pcall(vim.treesitter.get_parser, 0)
  if not has_parser or not parser then return nil end
  parser:parse()
  local ok, node = pcall(vim.treesitter.get_node)
  if not ok then return nil end
  while node do
    if vim.tbl_contains(types, node:type()) then return node end
    node = node:parent()
  end
end

local function text_of(node) return node and vim.treesitter.get_node_text(node, 0) or nil end

--- Name of the function / method the cursor is in.
local function function_name(types)
  local node = enclosing(types)
  local name = node and node:field('name')[1]
  if node and not name then -- Kotlin has no `name` field: the first identifier child
    for child in node:iter_children() do
      if child:type() == 'simple_identifier' or child:type() == 'identifier' then name = child; break end
    end
  end
  return text_of(name)
end

--- Names of all functions in the buffer matching `pattern` (one per line start).
local function names_in_file(pattern)
  local names = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local name = line:match(pattern)
    if name then names[#names + 1] = name end
  end
  return names
end

local no_test_here = 'The cursor is not inside a test: <leader>rf runs this file\'s tests.'

-- One builder per language: (kind, file, dir) -> { cmd, cwd } or nil, reason.
-- `kind` is 'nearest', 'file' or 'all'.
local builders = {}

function builders.go(kind, _, dir)
  if kind == 'all' then
    return { cmd = { 'go', 'test', './...' }, cwd = folder_with(dir, { 'go.work' }) or folder_with(dir, { 'go.mod' }) or dir }
  end
  local names
  if kind == 'nearest' then
    local name = function_name({ 'function_declaration' })
    if not name or not name:match('^Test') then return nil, no_test_here end
    names = { name }
  else
    names = names_in_file('^func%s+(Test[%w_]*)%s*%(')
    if #names == 0 then return nil, 'No Test... functions in this file.' end
  end
  local filter = #names == 1 and ('^' .. names[1] .. '$') or ('^(' .. table.concat(names, '|') .. ')$')
  return { cmd = { 'go', 'test', '-v', '-run', filter, '.' }, cwd = dir }
end

function builders.rust(kind, file, dir)
  local root = folder_with(dir, { 'Cargo.toml' })
  if not root then return nil, 'No Cargo.toml above this file.' end
  if kind == 'all' then return { cmd = { 'cargo', 'test' }, cwd = folder_with(dir, { 'Cargo.lock' }) or root } end
  if kind == 'nearest' then
    local name = function_name({ 'function_item' })
    if not name then return nil, no_test_here end
    return { cmd = { 'cargo', 'test', name }, cwd = root }
  end
  local relative = file:sub(#root + 2)
  local integration = relative:match('^tests/([^/]+)%.rs$')
  if integration then return { cmd = { 'cargo', 'test', '--test', integration }, cwd = root } end
  -- src/a/b.rs is the module a::b; the crate's root file holds everything
  local module = relative:match('^src/(.+)%.rs$')
  if not module or module == 'lib' or module == 'main' then return { cmd = { 'cargo', 'test' }, cwd = root } end
  module = module:gsub('/mod$', ''):gsub('/', '::')
  return { cmd = { 'cargo', 'test', module .. '::' }, cwd = root }
end

function builders.java(kind, file, dir)
  local class = vim.fn.fnamemodify(file, ':t:r')
  local package = names_in_file('^%s*package%s+([%w_.]+)')[1]
  local qualified = package and (package .. '.' .. class) or class
  local method
  if kind == 'nearest' then
    method = function_name({ 'method_declaration', 'function_declaration' })
    if not method then return nil, no_test_here end
  end
  local gradle = folder_with(dir, { 'gradlew' })
  if gradle then
    if kind == 'all' then return { cmd = { './gradlew', 'test' }, cwd = gradle } end
    return { cmd = { './gradlew', 'test', '--tests', method and (qualified .. '.' .. method) or qualified }, cwd = gradle }
  end
  local maven = folder_with(dir, { 'pom.xml' })
  if maven then
    if kind == 'all' then return { cmd = { 'mvn', 'test' }, cwd = maven } end
    return { cmd = { 'mvn', 'test', '-Dtest=' .. (method and (class .. '#' .. method) or class) }, cwd = maven }
  end
  return nil, 'No gradlew or pom.xml above this file.'
end
builders.kotlin = builders.java

function builders.cs(kind, file, dir)
  local project = folder_with(dir, {}, { '%.csproj$' })
  if not project then return nil, 'No .csproj above this file.' end
  if kind == 'all' then return { cmd = { 'dotnet', 'test' }, cwd = folder_with(dir, {}, { '%.slnx?$' }) or project } end
  local class = vim.fn.fnamemodify(file, ':t:r')
  if kind == 'file' then return { cmd = { 'dotnet', 'test', '--filter', 'FullyQualifiedName~' .. class }, cwd = project } end
  local method = function_name({ 'method_declaration' })
  if not method then return nil, no_test_here end
  local class_node = enclosing({ 'class_declaration' })
  class = text_of(class_node and class_node:field('name')[1]) or class
  return { cmd = { 'dotnet', 'test', '--filter', ('FullyQualifiedName~%s.%s'):format(class, method) }, cwd = project }
end

--- The title of the test() / it() / describe() call the cursor is in.
local function js_test_title()
  local node = enclosing({ 'call_expression' })
  while node do
    local callee = text_of(node:field('function')[1]) or ''
    if callee:match('^test') or callee:match('^it') or callee:match('^describe') then
      local first = node:field('arguments')[1] and node:field('arguments')[1]:named_child(0)
      local title = text_of(first)
      if title then return (title:gsub('^[\'"`]', ''):gsub('[\'"`]$', '')) end
    end
    node = node:parent()
    while node and node:type() ~= 'call_expression' do node = node:parent() end
  end
end

function builders.typescript(kind, file, dir)
  local root = folder_with(dir, { 'package.json' })
  if not root then return nil, 'No package.json above this file.' end
  local runner, name_flag
  if vim.uv.fs_stat(root .. '/bun.lock') or vim.uv.fs_stat(root .. '/bun.lockb') then
    runner, name_flag = { 'bun', 'test' }, '-t'
  elseif vim.uv.fs_stat(root .. '/node_modules/.bin/vitest') then
    runner, name_flag = { 'node_modules/.bin/vitest', 'run' }, '-t'
  elseif vim.uv.fs_stat(root .. '/node_modules/.bin/jest') then
    runner, name_flag = { 'node_modules/.bin/jest' }, '-t'
  else
    return nil, 'No test runner found for this project (looked for bun.lock, then vitest and jest in node_modules).'
  end
  if kind == 'all' then return { cmd = runner, cwd = root } end
  local cmd = vim.list_extend(vim.deepcopy(runner), { file })
  if kind == 'nearest' then
    local title = js_test_title()
    if not title then return nil, no_test_here end
    vim.list_extend(cmd, { name_flag, title })
  end
  return { cmd = cmd, cwd = root }
end
builders.javascript = builders.typescript
builders.typescriptreact = builders.typescript
builders.javascriptreact = builders.typescript

--- The command for `kind` ('nearest' | 'file' | 'all') in the current buffer:
--- { cmd = { program, args... }, cwd = folder }, or nil and why not.
function M.command(kind)
  local filetype = vim.bo.filetype
  local build = builders[filetype]
  if not build then
    return nil, ('No test command is known for %s files (the list is in lua/czernous/test.lua).'):format(filetype ~= '' and filetype or 'these')
  end
  local file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  return build(kind, file, vim.fs.dirname(file))
end

--- Enter on a `path:line` in the output: close the window and go there.
local function jump(win, cwd)
  local path, line = vim.api.nvim_get_current_line():match('([%w%._/%-]+%.%w+):(%d+)')
  if not path then return end
  if path:sub(1, 1) ~= '/' then path = cwd .. '/' .. path end
  if not vim.uv.fs_stat(path) then return end
  vim.api.nvim_win_close(win, true)
  vim.cmd.edit(vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(line), 0 })
end

--- Run `what.cmd` in `what.cwd`, showing its output in a floating terminal.
local function show(what)
  local program = what.cmd[1]
  local buf = vim.api.nvim_create_buf(false, true)
  local width, height = math.floor(vim.o.columns * 0.9), math.floor(vim.o.lines * 0.8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1, col = math.floor((vim.o.columns - width) / 2),
    title = ' ' .. table.concat(what.cmd, ' ') .. ' ', title_pos = 'left',
    footer = ' running...   q close ', footer_pos = 'right',
  })
  -- `./gradlew` means the project's own script: Neovim would look for it in
  -- its own working directory, so spell out where it is
  local argv = vim.deepcopy(what.cmd)
  if program:sub(1, 2) == './' then argv[1] = what.cwd .. program:sub(2) end
  local started, job = pcall(vim.fn.jobstart, argv, {
    term = true,
    cwd = what.cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) then return end
        local outcome = code == 0 and 'passed' or ('failed (exit code %d)'):format(code)
        vim.api.nvim_win_set_config(win, { footer = (' %s   q close   Enter on file:line jumps there '):format(outcome), footer_pos = 'right' })
      end)
    end,
  })
  if not started or job <= 0 then
    vim.api.nvim_win_close(win, true)
    vim.notify(('Cannot run the tests: `%s` could not be started (is it on $PATH, and executable?).'):format(program), vim.log.levels.WARN)
    return false
  end
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('normal! G') -- follow the output as it arrives
  vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true, desc = 'Close the test output' })
  vim.keymap.set('n', '<CR>', function() jump(win, what.cwd) end, { buffer = buf, desc = 'Go to the file:line on this line' })
  return true
end

--- Run tests: `kind` is 'nearest', 'file', 'all', or 'last' (repeat the previous run).
function M.run(kind)
  local what, why
  if kind == 'last' then
    what, why = M.last, 'No tests have been run yet in this session.'
  else
    what, why = M.command(kind)
  end
  if not what then return vim.notify(why, vim.log.levels.WARN) end
  -- tests run what is on disk
  if vim.bo.buftype == '' and vim.bo.modified and vim.api.nvim_buf_get_name(0) ~= '' then vim.cmd('silent! update') end
  if show(what) then M.last = what end
end

return M
