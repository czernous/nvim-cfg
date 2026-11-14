-- The start screen: what you see when Neovim opens with no file.
--
-- A plain buffer, no plugin: how long startup took, and the handful of keys that
-- get you somewhere. It is drawn after startup has finished (so it costs nothing
-- at launch), every key works on it as usual, and it disappears as soon as you
-- open a file.
--
-- The keys listed come from keymaps.lua, so they can't go out of date: change a
-- key there and this screen follows.

local M = {}

-- Which keys to show (by the keys you press), in this order. Their descriptions
-- are looked up in keymaps.lua.
local shown = { '<leader>pf', '<leader>pg', '<leader>?', '<leader>pv', '<C-e>', '<leader>ee', '<leader>gs', '<leader>pk' }

local function key_lines()
  local desc = {}
  for _, key in ipairs(require('czernous.keymaps').all()) do
    if key.mode == 'n' then desc[key.lhs] = key.desc end
  end
  local leader = vim.g.mapleader == ' ' and 'Space ' or (vim.g.mapleader or '\\')
  local lines = {}
  for _, lhs in ipairs(shown) do
    if desc[lhs] then
      local keys = lhs:gsub('<leader>', leader):gsub('<C%-(.)>', 'Ctrl-%1')
      -- short form: drop any "(...)" detail and the capital letter
      local text = desc[lhs]:gsub('%s*%b()', ''):gsub('^%u', string.lower)
      lines[#lines + 1] = ('%-12s %s'):format(keys, text)
    end
  end
  lines[#lines + 1] = ('%-12s %s'):format(leader:gsub('%s+$', ''), 'wait a moment: shows every key')
  return lines
end

local function startup_ms()
  -- lazy.nvim measures from process start to the first screen
  local ok, lazy = pcall(require, 'lazy')
  local ms = ok and lazy.stats().startuptime or 0
  if ms == 0 then
    -- no UI attached yet (or headless): the time this process has used so far
    local ok_stats, stats = pcall(require, 'lazy.stats')
    ms = ok_stats and stats.cputime() or 0
  end
  return ms > 0 and ('ready in %.1f ms'):format(ms) or nil
end

local function render(buf, win)
  local body = { 'N E O V I M', '' }
  vim.list_extend(body, key_lines())
  body[#body + 1] = ''
  body[#body + 1] = startup_ms() or ''
  -- centre the block in the window
  local width = 0
  for _, line in ipairs(body) do width = math.max(width, vim.fn.strdisplaywidth(line)) end
  local pad = string.rep(' ', math.max(0, math.floor((vim.api.nvim_win_get_width(win) - width) / 2)))
  local top = math.max(0, math.floor((vim.api.nvim_win_get_height(win) - #body) / 2) - 1)
  local lines = {}
  for _ = 1, top do lines[#lines + 1] = '' end
  for i, line in ipairs(body) do
    if i == 1 or i == #body then
      -- title and timing are centred on their own
      local own = string.rep(' ', math.max(0, math.floor((vim.api.nvim_win_get_width(win) - vim.fn.strdisplaywidth(line)) / 2)))
      lines[#lines + 1] = own .. line
    else
      lines[#lines + 1] = pad .. line
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  -- quiet colours: title in the normal text colour, everything else dimmed
  local ns = vim.api.nvim_create_namespace('czernous_start')
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i = top, #lines - 1 do
    vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_row = i + 1, hl_group = i == top and 'Title' or 'Comment' })
  end
end

--- Show the start screen if Neovim was started with nothing to edit.
---@param started_on_folder boolean `nvim <folder>`: replace the folder listing
function M.show(started_on_folder)
  if started_on_folder then
    -- Neovim opened the folder in its file explorer; swap that for an empty buffer.
    local listing = vim.api.nvim_get_current_buf()
    vim.cmd('silent! %argdelete')
    vim.cmd('enew')
    pcall(vim.api.nvim_buf_delete, listing, { force = true })
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.fn.argc() > 0 or vim.api.nvim_buf_get_name(buf) ~= '' or vim.bo[buf].modified
    or vim.api.nvim_buf_line_count(buf) > 1 or vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= '' then
    return -- a file, piped input, or something already typed
  end
  local win = vim.api.nvim_get_current_win()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe' -- gone as soon as another buffer takes its place
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'czstart'
  local restore = { number = vim.wo[win].number, relativenumber = vim.wo[win].relativenumber, signcolumn = vim.wo[win].signcolumn, cursorline = vim.wo[win].cursorline }
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn, vim.wo[win].cursorline = false, false, 'no', false
  render(buf, win)

  local group = vim.api.nvim_create_augroup('czernous_start', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', { group = group, buffer = buf, callback = function() render(buf, win) end })
  -- Leaving the screen: give the window its normal look back.
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        for option, value in pairs(restore) do vim.wo[win][option] = value end
      end
    end,
  })
end

return M
