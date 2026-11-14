-- Language server support. Server setup is in lua/czernous/lsp.lua;
-- keys are in keymaps.lua (group 'LSP').
return {
  {
    'neovim/nvim-lspconfig', -- provides default configs for each server
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} }, -- :Mason, installs servers
      'mason-org/mason-lspconfig.nvim',
      { 'j-hui/fidget.nvim', opts = {} }, -- LSP progress messages
    },
  },
  {
    -- Neovim API types/completion while editing this config (Lua).
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },
}
