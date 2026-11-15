-- Violation: per-buffer state that is never released.
local M = {}
local state = {}
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function(ev) state[ev.buf] = { opened = true } end,
})
function M.count() return vim.tbl_count(state) end
return M
