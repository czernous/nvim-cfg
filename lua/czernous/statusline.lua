-- The statusline: one quiet line with what you need and nothing else.
--
--   NORMAL  src/main.go [+]   git:main   E2 W1 H3                go   12:8
--   mode    file  modified    branch     problems          filetype   line:column
--   (`debug:stopped` / `debug:running` after the mode while debugging;
--    E errors, W warnings, I information, H hints -- only the ones present;
--    `fix` after them when a fix is offered on the cursor's line: <leader>ef)
--
-- Built in, no plugin. Costs nothing while you move around: the mode, branch and
-- problem counts are plain text written into the 'statusline' option only when
-- one of them changes (mode change, new diagnostics, entering a buffer, git
-- update). The file name and cursor position are Neovim's own built-in items,
-- so redrawing the line runs no Lua at all.
--
-- Plain text only: no icons or special symbols, so it looks the same in any
-- terminal font. Colours come from the active theme (see M.highlights); backgrounds are left
-- alone so the line is transparent with the rest of the UI.

local M = {}

local mode_names = {
  n = 'NORMAL', no = 'PENDING', i = 'INSERT', ic = 'INSERT', R = 'REPLACE', Rv = 'REPLACE',
  v = 'VISUAL', V = 'V-LINE', ['\22'] = 'V-BLOCK', s = 'SELECT', S = 'S-LINE', ['\19'] = 'S-BLOCK',
  c = 'COMMAND', t = 'TERMINAL', nt = 'NORMAL', r = 'PROMPT', ['!'] = 'SHELL',
}
-- Which highlight each mode's word uses: only the mode word is ever coloured.
local mode_hl = {
  INSERT = 'CzStlInsert', VISUAL = 'CzStlVisual', ['V-LINE'] = 'CzStlVisual', ['V-BLOCK'] = 'CzStlVisual',
  REPLACE = 'CzStlReplace', COMMAND = 'CzStlCommand', TERMINAL = 'CzStlInsert',
}

--- Text shown literally must have its % doubled ('statusline' treats % as code).
local function literal(text) return (text:gsub('%%', '%%%%')) end

local function mode_part()
  local mode = vim.api.nvim_get_mode().mode
  local name = mode_names[mode] or mode_names[mode:sub(1, 1)] or mode:upper()
  return ('%%#%s# %s %%#CzStlText#'):format(mode_hl[name] or 'CzStlNormal', name)
end

local function git_part(buf)
  local head = vim.b[buf].gitsigns_head
  if not head or head == '' then return '' end
  -- Bound branch text before escaping statusline syntax; preserve filename space.
  local limit = math.max(8, math.min(24, math.floor(vim.o.columns / 4)))
  if vim.fn.strdisplaywidth(head) > limit then
    head = vim.fn.strcharpart(head, 0, limit - 3) .. '...'
  end
  -- plain text, so it reads as a branch (not part of the path) in any font
  return ('   %%#CzStlDim#git:%s%%#CzStlText#'):format(literal(head))
end

local function debug_part()
  -- only once the debugger has been used (it loads on the first <leader>b key)
  local debugging = package.loaded['czernous.debugging']
  local state = debugging and debugging.state()
  return state and ('  %%#CzStlWarn#debug:%s%%#CzStlText#'):format(state) or ''
end

local function problems_part(buf)
  -- Neovim's diagnostics module costs ~1 ms to load; before it has been loaded
  -- (by the language-server setup, after the first screen) there is nothing to count.
  if not package.loaded['vim.diagnostic'] then return '' end
  local counts = vim.diagnostic.count(buf)
  local severity = vim.diagnostic.severity
  local out = {}
  -- E errors, W warnings, I information, H hints (suggestions); only those present
  for _, kind in ipairs({ { severity.ERROR, 'E', 'CzStlError' }, { severity.WARN, 'W', 'CzStlWarn' },
    { severity.INFO, 'I', 'CzStlInfo' }, { severity.HINT, 'H', 'CzStlHint' } }) do
    local n = counts[kind[1]] or 0
    if n > 0 then out[#out + 1] = ('%%#%s#%s%d'):format(kind[3], kind[2], n) end
  end
  if #out == 0 then return '' end
  -- `fix`: the language server offers a fix on the cursor's line (see fixes.lua)
  local fix = vim.b[buf].czernous_fix
  if fix and vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] - 1 == fix then
    out[#out + 1] = '%#CzStlHint#fix'
  end
  return '   ' .. table.concat(out, ' ') .. '%#CzStlText#'
end

--- Rebuild the line for the current window and store it in the option. Called
--- only from the events registered in M.setup -- never on cursor movement.
function M.update()
  -- Popups and plugins' hidden helper windows (progress messages, pickers,
  -- completion) are not what the line describes: keep showing the file's info.
  if vim.api.nvim_win_get_config(0).relative ~= '' then return end
  local buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[buf].filetype
  if vim.b[buf].czernous_start then -- the start screen: nothing to report yet
    if vim.o.statusline ~= ' ' then vim.o.statusline = ' ' end
    return
  end
  local line = table.concat({
    mode_part(),
    debug_part(),
    ' %<%f%( %#CzStlDim#%m%r%#CzStlText#%)', -- file name, [+] if modified, [RO] if read-only
    git_part(buf),
    vim.bo[buf].buftype == '' and problems_part(buf) or '',
    '%=', -- everything after this is right-aligned
    filetype ~= '' and ('%#CzStlDim#' .. literal(filetype) .. '%#CzStlText#   ') or '',
    '%l:%c ',
  })
  if vim.o.statusline ~= line then vim.o.statusline = line end
end

--- Highlight groups, taken from the active theme: foreground only, no background.
function M.highlights()
  local function fg(group) return vim.api.nvim_get_hl(0, { name = group, link = false }).fg end
  local set = vim.api.nvim_set_hl
  set(0, 'CzStlText', { fg = fg('Normal') })
  set(0, 'CzStlDim', { fg = fg('Comment') })
  set(0, 'CzStlNormal', { fg = fg('Normal'), bold = true })
  set(0, 'CzStlInsert', { fg = fg('String'), bold = true })
  set(0, 'CzStlVisual', { fg = fg('Keyword'), bold = true })
  set(0, 'CzStlReplace', { fg = fg('DiagnosticError'), bold = true })
  set(0, 'CzStlCommand', { fg = fg('Constant'), bold = true })
  set(0, 'CzStlError', { fg = fg('DiagnosticError') })
  set(0, 'CzStlWarn', { fg = fg('DiagnosticWarn') })
  set(0, 'CzStlInfo', { fg = fg('DiagnosticInfo') })
  set(0, 'CzStlHint', { fg = fg('DiagnosticHint') })
end

function M.setup()
  vim.o.laststatus = 3    -- one statusline for the whole screen, not one per split
  vim.o.showmode = false  -- the statusline already shows the mode
  M.highlights()
  -- Events often arrive in bursts (opening a file fires several) and sometimes
  -- from inside another buffer's context; refresh once, on the next tick, when
  -- things have settled.
  local pending = false
  local function refresh()
    if pending then return end
    pending = true
    vim.schedule(function()
      pending = false
      M.update()
    end)
  end
  local group = vim.api.nvim_create_augroup('czernous_statusline', { clear = true })
  vim.api.nvim_create_autocmd({ 'ModeChanged', 'BufEnter', 'WinEnter', 'VimResized', 'DiagnosticChanged', 'FileType', 'TermOpen' }, {
    group = group,
    desc = 'Refresh the statusline text',
    callback = refresh,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'GitSignsUpdate',
    desc = 'Refresh the statusline branch',
    callback = refresh,
  })
  -- The theme changed (dark/light switch, transparency toggle): take its colours again.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'CzernousTheme',
    desc = 'Re-colour the statusline',
    callback = function() M.highlights() end,
  })
  M.update()
end

return M
