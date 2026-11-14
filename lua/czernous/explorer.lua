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

local M = {}

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

return M
