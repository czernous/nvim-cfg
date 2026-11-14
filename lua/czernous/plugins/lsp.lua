-- Language server support. Server setup is in lua/czernous/lsp.lua;
-- keys are in keymaps.lua (group 'LSP').
return {
  {
    -- Default settings for each server (data only). Loaded by lsp.lua just
    -- before it enables servers, after the first screen.
    'neovim/nvim-lspconfig',
    event = 'User CzernousLspSetup',
  },
  {
    -- :Mason / :MasonInstall <server> -- manual fallback for machines without
    -- the language toolchain. PATH = 'append': toolchain/devshell copies win.
    -- Loaded with lspconfig so its bin folder is on $PATH before servers are
    -- looked up.
    'mason-org/mason.nvim',
    event = 'User CzernousLspSetup',
    cmd = { 'Mason', 'MasonInstall', 'MasonUninstall', 'MasonUpdate', 'MasonLog' },
    opts = { PATH = 'append' },
  },
  -- LSP progress messages. Loads when a server attaches.
  { 'j-hui/fidget.nvim', event = 'LspAttach', opts = {} },
  {
    -- Neovim API types/completion while editing this config (Lua files only).
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
}
