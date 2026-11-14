-- The statusline: one quiet line with what you need and nothing else.
--
--   NORMAL  src/main.go [+]   main   E2 W1                      go   12:8
--   mode    file  modified    branch errors/warnings      filetype   line:column
--
-- Built in, no plugin. Costs nothing while you move around: the mode, branch and
-- problem counts are plain text written into the 'statusline' option only when
-- one of them changes (mode change, new diagnostics, entering a buffer, git
-- update). The file name and cursor position are Neovim's own built-in items,
-- so redrawing the line runs no Lua at all.
--
-- Colours come from the active theme (see M.highlights); backgrounds are left
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
  return ('  %%#CzStlDim#%s%%#CzStlText#'):format(literal(head))
end

local function problems_part(buf)
  local counts = vim.diagnostic.count(buf)
  local errors = counts[vim.diagnostic.severity.ERROR] or 0
  local warnings = counts[vim.diagnostic.severity.WARN] or 0
  local out = ''
  if errors > 0 then out = out .. ('  %%#CzStlError#E%d'):format(errors) end
  if warnings > 0 then out = out .. ('%s%%#CzStlWarn#W%d'):format(errors > 0 and ' ' or '  ', warnings) end
  if out ~= '' then out = out .. '%#CzStlText#' end
  return out
end

--- Rebuild the line for the current window and store it in the option. Called
--- only from the events registered in M.setup -- never on cursor movement.
function M.update()
  -- Popups and plugins' hidden helper windows (progress messages, pickers,
  -- completion) are not what the line describes: keep showing the file's info.
  if vim.api.nvim_win_get_config(0).relative ~= '' then return end
  local buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[buf].filetype
  local line = table.concat({
    mode_part(),
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
  vim.api.nvim_create_autocmd({ 'ModeChanged', 'BufEnter', 'WinEnter', 'DiagnosticChanged', 'FileType', 'TermOpen' }, {
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
