-- Violation: a UI element that keeps painting one of the theme's background
-- shades (so it is NOT transparent). It re-paints every few milliseconds because
-- the theme repairs such groups whenever a plugin loads; the check must still
-- catch one that is wrong at the moment it looks. tripwire: opaque
vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy',
  once = true,
  callback = function()
    local timer = vim.uv.new_timer()
    timer:start(0, 10, vim.schedule_wrap(function()
      local shade = next(require('czernous.theme').shades)
      if shade then vim.api.nvim_set_hl(0, 'TripwireOpaquePanel', { bg = shade }) end
    end))
  end,
})
return {}
