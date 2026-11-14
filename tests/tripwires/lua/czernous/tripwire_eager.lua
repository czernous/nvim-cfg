-- Violation: pulls a plugin in before the first screen. tripwire: eager
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyDone',
  callback = function() require('telescope') end,
})
return {}
