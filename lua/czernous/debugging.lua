-- Debugging: breakpoints, stepping, looking at variables. Keys: <leader>b...
--
--   <leader>bb  breakpoint on this line (again to remove)   B in the margin
--   <leader>bc  start debugging / continue to the next breakpoint
--   <leader>bn  next line     <leader>bi  into the call     <leader>bo  out of it
--   <leader>bv  variables     <leader>bs  call stack        <leader>be  value under the cursor
--   <leader>br  console (type expressions)                  <leader>bq  stop
--
-- The line the program is paused on is marked `>`; the statusline shows
-- `debug:stopped` or `debug:running` while a session lasts.
--
-- Debugger programs come from $PATH (the language toolchain or a devshell);
-- nothing is installed from here. They are looked up in the background the
-- first time you start debugging a language; a missing one gives one message
-- that names it. A project's .vscode/launch.json is offered when it has one.
-- :checkhealth czernous lists the programs.

local M = {}

--- Ask for a path (with file completion) when a session starts. nvim-dap waits
--- for the answer without blocking the editor; an empty answer cancels the start.
local function ask_path(prompt, default)
  return function()
    return coroutine.create(function(caller)
      vim.ui.input({ prompt = prompt, default = default(), completion = 'file' }, function(answer)
        coroutine.resume(caller, (answer and answer ~= '') and answer or require('dap').ABORT)
      end)
    end)
  end
end

-- One entry per debugger. `programs`: the first one found on $PATH is used.
-- `configure(dap, program, path)` registers it and how to start a session.
M.debuggers = {
  {
    filetypes = { 'go' },
    programs = { 'dlv' },
    what = 'Delve, the Go debugger',
    configure = function(dap, _, path)
      dap.adapters.go = {
        type = 'server',
        port = '${port}',
        executable = { command = path, args = { 'dap', '-l', '127.0.0.1:${port}' } },
      }
      dap.configurations.go = {
        {
          type = 'go',
          request = 'launch',
          name = "Debug this file's package (its tests, from a _test.go file)",
          mode = function() return vim.api.nvim_buf_get_name(0):match('_test%.go$') and 'test' or 'debug' end,
          program = '${fileDirname}',
        },
      }
    end,
  },
  {
    filetypes = { 'rust', 'c', 'cpp' },
    programs = { 'lldb-dap', 'codelldb' },
    what = 'the LLDB debugger',
    configure = function(dap, program, path)
      local kind = program == 'codelldb' and 'codelldb' or 'lldb'
      if kind == 'codelldb' then
        dap.adapters.codelldb = { type = 'server', port = '${port}', executable = { command = path, args = { '--port', '${port}' } } }
      else
        dap.adapters.lldb = { type = 'executable', command = path, name = 'lldb' }
      end
      local start = {
        {
          type = kind,
          request = 'launch',
          name = 'Debug a built program',
          -- Build first (cargo build / make): the debugger runs what is on disk.
          program = ask_path('Program to debug (build it first): ', function()
            local cwd = vim.uv.cwd() or '.'
            return cwd .. '/target/debug/' .. vim.fs.basename(cwd)
          end),
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
        },
      }
      dap.configurations.rust, dap.configurations.c, dap.configurations.cpp = start, start, start
    end,
  },
  {
    filetypes = { 'cs' },
    programs = { 'netcoredbg' },
    what = 'the .NET debugger',
    configure = function(dap, _, path)
      dap.adapters.coreclr = { type = 'executable', command = path, args = { '--interpreter=vscode' } }
      dap.configurations.cs = {
        {
          type = 'coreclr',
          request = 'launch',
          name = 'Debug a built .dll',
          program = ask_path('The .dll to debug (build it first: dotnet build): ', function()
            return (vim.uv.cwd() or '.') .. '/bin/Debug/'
          end),
        },
      }
    end,
  },
}

-- Languages that need more than a program on $PATH, and what to say about them.
local not_yet = {
  java = 'Java debugging is not set up yet: it needs the java-debug extension inside jdtls, which will come with the Nix devshell.',
  kotlin = 'Kotlin debugging is not set up yet (it comes with the Java debugging setup).',
}

local function debugger_for(filetype)
  for _, debugger in ipairs(M.debuggers) do
    if vim.tbl_contains(debugger.filetypes, filetype) then return debugger end
  end
end

--- Make debugging ready for `filetype`: find its debugger program (background)
--- and register it. Calls back with `true`, or `false` and what to tell the user.
function M.prepare(filetype, callback)
  local debugger = debugger_for(filetype)
  if not debugger then
    return callback(false, not_yet[filetype]
      or ('No debugger is set up for %s files (the list is in lua/czernous/debugging.lua).'):format(filetype ~= '' and filetype or 'these'))
  end
  require('czernous.tools').locate(debugger.programs, function(where)
    for _, program in ipairs(debugger.programs) do
      if where[program] then
        debugger.configure(require('dap'), program, where[program])
        return callback(true)
      end
    end
    callback(false, ('Cannot debug %s files: %s (`%s`) is not on $PATH. It comes from the language toolchain or your devshell; :checkhealth czernous lists what is found.')
      :format(filetype, debugger.what, table.concat(debugger.programs, '` or `')))
  end)
end

--- nil when nothing is being debugged, else 'stopped' (paused on a line) or 'running'.
function M.state()
  local dap = package.loaded['dap']
  local session = dap and dap.session()
  if not session then return nil end
  return session.stopped_thread_id and 'stopped' or 'running'
end

--- Run `fn(dap)` if a session exists, else say how to start one.
local function in_session(fn)
  return function()
    local dap = require('dap')
    if not dap.session() then
      vim.notify('Nothing is being debugged: <leader>bb sets a breakpoint, <leader>bc starts.', vim.log.levels.INFO)
      return
    end
    fn(dap)
  end
end

function M.toggle_breakpoint() require('dap').toggle_breakpoint() end

function M.conditional_breakpoint()
  vim.ui.input({ prompt = 'Stop here only when (an expression in the language): ' }, function(condition)
    if condition and condition ~= '' then require('dap').set_breakpoint(condition) end
  end)
end

--- Start debugging the current file's program, or continue a paused one.
function M.continue()
  local dap = require('dap')
  if dap.session() then return dap.continue() end
  M.prepare(vim.bo.filetype, function(ready, message)
    if not ready then return vim.notify(message, vim.log.levels.WARN) end
    dap.continue()
  end)
end

--- Start the previous session again.
function M.run_last()
  M.prepare(vim.bo.filetype, function(ready, message)
    if not ready then return vim.notify(message, vim.log.levels.WARN) end
    require('dap').run_last()
  end)
end

M.step_over = in_session(function(dap) dap.step_over() end)
M.step_into = in_session(function(dap) dap.step_into() end)
M.step_out = in_session(function(dap) dap.step_out() end)
M.stop = in_session(function(dap) dap.terminate() end)
M.console = function() require('dap').repl.toggle({ height = 12 }) end
M.variables = in_session(function()
  local widgets = require('dap.ui.widgets')
  widgets.centered_float(widgets.scopes)
end)
M.stack = in_session(function()
  local widgets = require('dap.ui.widgets')
  widgets.centered_float(widgets.frames)
end)
M.value = in_session(function() require('dap.ui.widgets').hover() end)

--- Runs once, when nvim-dap loads (the first debug key).
function M.setup()
  local dap = require('dap')
  -- Markers in the margin: plain letters, coloured by the theme.
  local define = vim.fn.sign_define
  define('DapBreakpoint', { text = 'B', texthl = 'DiagnosticError' })
  define('DapBreakpointCondition', { text = 'C', texthl = 'DiagnosticError' })
  define('DapLogPoint', { text = 'L', texthl = 'DiagnosticInfo' })
  define('DapBreakpointRejected', { text = '?', texthl = 'DiagnosticHint' })
  define('DapStopped', { text = '>', texthl = 'DiagnosticWarn', linehl = 'CursorLine' })

  -- Which files a .vscode/launch.json entry of each debugger type is for.
  local types = require('dap.ext.vscode').type_to_filetypes
  types.go, types.coreclr = { 'go' }, { 'cs' }
  types.lldb, types.codelldb = { 'rust', 'c', 'cpp' }, { 'rust', 'c', 'cpp' }

  -- Keep the statusline's `debug:...` in step with the session.
  local function refresh() vim.schedule(require('czernous.statusline').update) end
  for _, event in ipairs({ 'event_initialized', 'event_stopped', 'event_continued', 'event_terminated', 'event_exited' }) do
    dap.listeners.after[event].czernous = refresh
  end
  dap.listeners.on_session.czernous = refresh
end

return M
