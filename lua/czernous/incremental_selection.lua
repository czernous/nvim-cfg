-- Grow/shrink a visual selection over treesitter syntax nodes.
-- (Replacement for nvim-treesitter master's removed `incremental_selection`.)
-- Keys are in keymaps.lua (Code structure group).
local M = {}
local selections = {} -- per-buffer stack of nodes

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

function M.grow()
  local buf = vim.api.nvim_get_current_buf()
  local stack = selections[buf]
  if not stack or #stack == 0 then return M.init() end
  local cur = stack[#stack]
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
