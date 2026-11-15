-- Violation: statusline work on every cursor move. tripwire: statusline
vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy',
  callback = function()
    vim.api.nvim_create_autocmd('CursorMoved', {
      group = vim.api.nvim_create_augroup('czernous_statusline', { clear = false }),
      desc = 'tripwire: recompute the statusline on every cursor move',
      callback = function() local _ = { vim.fn.mode(), vim.fn.line('.') } end,
    })
  end,
})
return {}
