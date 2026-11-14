-- Violation: a blocking PATH lookup at startup.
vim.fn.executable('some-tool-that-does-not-exist')
return {}
