-- Violation: a blocking lookup spelled so the runtime recorder can't see it.
-- tripwire: blocking_static
local M = {}
function M.never_called() return vim.call('executable', 'some-tool') end
return M
