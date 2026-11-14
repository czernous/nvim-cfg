-- Grow/shrink a visual selection over treesitter syntax nodes.
-- (Replacement for nvim-treesitter master's removed `incremental_selection`.)
-- Keys are in keymaps.lua (Code structure group).
local M = {}
local selections = {} -- per-buffer stack of nodes

-- Forget a buffer's stack when the buffer goes away; otherwise every buffer
-- ever selected in would keep its syntax tree alive for the whole session.
vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
  group = vim.api.nvim_create_augroup('czernous_incremental_selection', { clear = true }),
  callback = function(ev) selections[ev.buf] = nil end,
})

local function select_node(node)
  local srow, scol, erow, ecol = node:range()
  -- `normal! v` toggles: if we're already selecting it would END visual mode.
  if vim.fn.mode():match('^[vV\22]') then vim.cmd('normal! \27') end
  vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  vim.cmd('normal! v')
  if ecol == 0 then -- range end is exclusive; step back to previous line's end
    vim.api.nvim_win_set_cursor(0, { erow, 0 })
    vim.cmd('normal! $')
  else
    vim.api.nvim_win_set_cursor(0, { erow + 1, ecol - 1 })
  end
end

local function ranges_equal(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

function M.init()
  local buf = vim.api.nvim_get_current_buf()
  -- Parsing is async in 0.12; make sure the cursor's line is parsed.
  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then return end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  parser:parse({ row, row + 1 })
  local node = vim.treesitter.get_node()
  if not node then return end
  selections[buf] = { node }
  select_node(node)
end

--- Start (row, col) of the current visual selection, 0-based.
local function selection_start()
  local a, b = vim.fn.getpos('v'), vim.fn.getpos('.')
  if b[2] < a[2] or (b[2] == a[2] and b[3] < a[3]) then a = b end
  return a[2] - 1, a[3] - 1
end

function M.grow()
  local buf = vim.api.nvim_get_current_buf()
  local stack = selections[buf]
  if not stack or #stack == 0 then return M.init() end
  local cur = stack[#stack]
  -- Selection is somewhere else than last time: start over from here.
  local row, col = selection_start()
  local nrow, ncol = cur:range()
  if row ~= nrow or col ~= ncol then return M.init() end
  local parent = cur:parent()
  while parent and ranges_equal({ parent:range() }, { cur:range() }) do
    parent = parent:parent()
  end
  if parent then
    table.insert(stack, parent)
    select_node(parent)
  else
    select_node(cur)
  end
end

function M.shrink()
  local buf = vim.api.nvim_get_current_buf()
  local stack = selections[buf]
  if not stack or #stack <= 1 then return end
  table.remove(stack)
  select_node(stack[#stack])
end

return M
