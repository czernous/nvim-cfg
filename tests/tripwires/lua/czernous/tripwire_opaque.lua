-- Violation: a UI element painted with one of the theme's background shades, by
-- code that runs AFTER the theme has styled everything (so the theme's own
-- re-styling on plugin load cannot repair it). tripwire: opaque
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    -- registered after theme.lua's own handlers, so it runs after them each time
    vim.api.nvim_create_autocmd('User', {
      pattern = { 'VeryLazy', 'LazyLoad' },
      callback = function()
        local shade = next(require('czernous.theme').shades)
        if shade then vim.api.nvim_set_hl(0, 'TripwireOpaquePanel', { bg = shade }) end
      end,
    })
  end,
})
return {}
