-- Extras for the explorer (oil.nvim, <leader>pv).
--
-- `gm` -- move by typing, like the `mv` command: asks "Move to:" with the
-- entry's full path filled in (Tab completes folders), so a file can go
-- anywhere without cut / navigate / paste.
--   * folders that don't exist yet are created
--   * a destination that is a folder (or ends with /) means "into that folder"
--   * nothing is ever overwritten
-- The move goes through oil itself, so open buffers follow the file and
-- language servers are told (they update imports where they support it).
--
-- Git status -- two letters at the end of a line, as `git status --short` prints them:
--   first letter (green): staged for the next commit   A added  M modified  D deleted  R renamed
--   second letter:        changed but not staged       M modified  D deleted
--   ?  new, not tracked yet        !  ignored          (a folder shows what is inside it)
-- Asked from git in the background each time a folder is shown, so the listing
-- never waits for it. <leader>tg switches it off / on.

local M = {}

local namespace = vim.api.nvim_create_namespace('czernous_explorer_git')
local git_status_on = true

local function warn(text) vim.notify(text, vim.log.levels.WARN) end

function M.move()
  local oil = require('oil')
  local dir, entry = oil.get_current_dir(), oil.get_cursor_entry()
  if not dir or not entry then return end
  local from = dir .. entry.name
  vim.ui.input({ prompt = 'Move to: ', default = from, completion = 'file' }, function(answer)
    if not answer or answer == '' then return end
    local into_folder = answer:sub(-1) == '/'
    local to = vim.fs.normalize(vim.fn.fnamemodify(answer, ':p'))
    if into_folder or vim.fn.isdirectory(to) == 1 then to = to .. '/' .. entry.name end
    if to == from then return end
    if vim.uv.fs_stat(to) then return warn(('Not moved: %s already exists.'):format(to)) end
    if vim.startswith(to, from .. '/') then return warn('Not moved: a folder cannot go inside itself.') end
    vim.fn.mkdir(vim.fs.dirname(to), 'p')
    require('oil.mutator').process_actions({
      { type = 'move', entry_type = entry.type, src_url = 'oil://' .. from, dest_url = 'oil://' .. to },
    }, function(err)
      if err then return warn(('Not moved: %s'):format(err)) end
      -- show the folder as it is now (only if nothing else is being edited in it)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == 'oil' and vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
          vim.api.nvim_buf_call(buf, function() vim.cmd('silent! edit') end)
        end
      end
    end)
  end)
end

-- When a folder holds several changes, the letter that matters most wins.
local weight = { ['!'] = 1, ['?'] = 2, R = 3, C = 3, A = 4, D = 5, M = 6, U = 7 }
local function heavier(a, b) return (weight[a] or 0) >= (weight[b] or 0) and a or b end

--- git's answer -> { entry name = { staged letter, unstaged letter } } for one folder.
--- `output` is `<folder's path inside the repository>\n` + `git status --porcelain -z`.
local function parse(output)
  local prefix, rest = output:match('^([^\n]*)\n(.*)$')
  local status = {}
  if not prefix then return status end
  local records = vim.split(rest, '\0', { plain = true })
  local i = 1
  while i <= #records do
    local record = records[i]
    local staged, unstaged, path = record:sub(1, 1), record:sub(2, 2), record:sub(4)
    if staged == 'R' or staged == 'C' then i = i + 1 end -- the next record is the old name
    if path ~= '' and vim.startswith(path, prefix) then
      local name = path:sub(#prefix + 1):match('^[^/]+')
      if name then
        local seen = status[name] or { ' ', ' ' }
        status[name] = { heavier(staged, seen[1]), heavier(unstaged, seen[2]) }
      end
    end
    i = i + 1
  end
  return status
end

local function draw(buf, status)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  local oil = require('oil')
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    local entry = oil.get_entry_on_line(buf, lnum)
    local letters = entry and status[entry.name]
    if letters then
      local text
      if letters[1] == '?' or letters[1] == '!' then
        text = { { '   ' .. letters[1], 'Comment' } }
      else
        text = { { '   ' .. letters[1], 'Added' }, { letters[2], 'Changed' } }
      end
      vim.api.nvim_buf_set_extmark(buf, namespace, lnum - 1, 0, { virt_text = text, virt_text_pos = 'eol', hl_mode = 'combine' })
    end
  end
end

--- Ask git about the folder shown in `buf` (background) and mark its entries.
local function refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'oil' then return end
  local dir = require('oil').get_current_dir(buf)
  if not git_status_on or not dir then return vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1) end
  -- several refreshes may be on their way; only the latest one's answer is drawn
  local request = (vim.b[buf].czernous_git_request or 0) + 1
  vim.b[buf].czernous_git_request = request
  local script = 'git rev-parse --show-prefix && git -c core.quotepath=false status --porcelain -z --ignored -- .'
  -- pcall: no `git` program at all is not an error worth a message here
  pcall(vim.system, { 'sh', '-c', script }, { cwd = dir }, function(r)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].czernous_git_request ~= request then return end
      draw(buf, r.code == 0 and git_status_on and parse(r.stdout or '') or {})
    end)
  end)
end

local function refresh_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then refresh(buf) end
  end
end

function M.toggle_git_status()
  git_status_on = not git_status_on
  refresh_all()
  vim.notify('Git status in the explorer: ' .. (git_status_on and 'on' or 'off'))
end

--- Runs once, when the explorer loads.
function M.setup()
  local group = vim.api.nvim_create_augroup('czernous_explorer', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'OilEnter',
    desc = 'Show git status in the explorer',
    callback = function(ev) refresh(ev.data and ev.data.buf or ev.buf) end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'OilMutationComplete', 'OilActionsPost' },
    desc = 'Git status again after files changed',
    -- a moment later: the explorer redraws its listing first
    callback = function() vim.defer_fn(refresh_all, 100) end,
  })
end

return M
