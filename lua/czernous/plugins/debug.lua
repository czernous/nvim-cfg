-- Debugging. Everything about it (which debugger programs, the markers, what
-- the keys do) is in lua/czernous/debugging.lua; keys are in keymaps.lua (group
-- 'Debugging', <leader>b...).
return {
  {
    -- Talks to debugger programs (the same protocol VS Code uses). Loads on the
    -- first debug key; no separate UI plugin -- its own popups and a plain
    -- console buffer are enough.
    'mfussenegger/nvim-dap',
    config = function() require('czernous.debugging').setup() end,
  },
}
