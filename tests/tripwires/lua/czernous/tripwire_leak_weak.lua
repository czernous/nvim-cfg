-- Violation: per-buffer flags in a "weak" table. Weak tables do NOT free number
-- keys, so this still leaks one entry per buffer. tripwire: leak_weak
local M = {}
local attached = setmetatable({}, { __mode = 'k' })
vim.api.nvim_create_autocmd('BufEnter', { callback = function(ev) attached[ev.buf] = true end })
function M.count() return vim.tbl_count(attached) end
return M
