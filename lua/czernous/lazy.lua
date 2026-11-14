-- Plugins normally live under Neovim's data folder and are fetched from the
-- lockfile. They may instead be supplied from outside (e.g. a read-only Nix
-- store path) by setting $NVIM_PLUGIN_ROOT: then nothing is installed or
-- written there.
local external = vim.env.NVIM_PLUGIN_ROOT
local plugin_root = external or (vim.fn.stdpath('data') .. '/lazy')
local lazypath = plugin_root .. '/lazy.nvim'
if not external and not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none', 'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup('czernous.plugins', {
  root = plugin_root,
  lockfile = external and (vim.fn.stdpath('state') .. '/lazy-lock.json') or nil,
  install = { missing = not external },
  -- Nothing loads at startup unless a spec says `lazy = false` (only the theme
  -- does). Every other plugin names what loads it: a key, a command, a file
  -- opening, insert mode... See each spec in lua/czernous/plugins/.
  defaults = { lazy = true },
  -- No plugin here uses luarocks; disabling it avoids health errors and a bootstrap.
  rocks = { enabled = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      -- Built-in plugins this config never uses.
      disabled_plugins = { 'gzip', 'tarPlugin', 'tohtml', 'tutor', 'zipPlugin', 'rplugin', 'spellfile', 'osc52' },
    },
  },
})
