-- Violation: deprecated API (vim.loop was renamed vim.uv).
local uv = vim.loop
return { uv = uv }
