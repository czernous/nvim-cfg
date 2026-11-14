-- Language servers.
--
-- A server starts only if its program is on $PATH: from the language's own
-- toolchain (rustup, go install, dotnet tool) or a Nix devshell. Mason is a
-- manual fallback (:MasonInstall <name>); its bin dir is at the END of $PATH,
-- so a toolchain/devshell copy always wins. Language/SDK versions are chosen by
-- the environment you start Neovim in, never here.
--
-- Adding a language: one line in M.servers  (lspconfig name = program name).
-- Special settings for a server go in after/lsp/<name>.lua.
-- Keys for LSP buffers are in keymaps.lua (group 'LSP').

local M = {}

M.servers = {
  gopls = 'gopls',
  rust_analyzer = 'rust-analyzer',
  lua_ls = 'lua-language-server',
  jdtls = 'jdtls',
  csharp_ls = 'csharp-ls',
  vtsls = 'vtsls',
}

--- Names of servers enabled at startup (filled by M.setup).
M.enabled = {}

function M.setup()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('czernous_lsp', { clear = true }),
    desc = 'LSP keymaps and :Format',
    callback = function(event)
      require('czernous.keymaps').lsp(event.buf)
      vim.api.nvim_buf_create_user_command(event.buf, 'Format', function()
        vim.lsp.buf.format()
      end, { desc = 'Format current buffer with LSP' })
    end,
  })

  -- nvim-cmp completion capabilities for every server.
  vim.lsp.config('*', { capabilities = require('cmp_nvim_lsp').default_capabilities() })

  M.enabled = {}
  for name, exe in pairs(M.servers) do
    if vim.fn.executable(exe) == 1 then
      vim.lsp.enable(name)
      table.insert(M.enabled, name)
    end
  end
  table.sort(M.enabled)
end

return M
