-- Violation: a blocking PATH lookup AFTER startup (e.g. in a lazily loaded
-- plugin's setup). tripwire: blocking_late
vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy',
  callback = function() vim.fn.executable('some-tool-that-does-not-exist') end,
})
return {}
