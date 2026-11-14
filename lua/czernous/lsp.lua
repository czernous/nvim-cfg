-- [[ Configure LSP ]]
-- Keymaps for LSP buffers are in keymaps.lua (group 'LSP').
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP keymaps and :Format',
  callback = function(event)
    require('czernous.keymaps').lsp(event.buf)
    vim.api.nvim_buf_create_user_command(event.buf, 'Format', function(_)
      vim.lsp.buf.format()
    end, { desc = 'Format current buffer with LSP' })
  end,
})

-- Lua nvim-API types/completion are provided by lazydev.nvim (see plugins/lsp.lua),
-- which configures itself on the `lua` filetype -- no setup call needed here.
-- (Replaces the archived neodev.nvim.)

-- nvim-cmp completion capabilities, broadcast to every server via the '*' config.
local capabilities = require('cmp_nvim_lsp').default_capabilities()
vim.lsp.config('*', {
  capabilities = capabilities,
})

-- Per-server overrides live here ONLY for special behavior (custom settings or
-- language extensions). Plain servers need nothing beyond being installed.
vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
      -- NOTE: toggle below to ignore Lua_LS's noisy `missing-fields` warnings
      -- diagnostics = { disable = { 'missing-fields' } },
    },
  },
})

-- Rust + Leptos: use leptosfmt for formatting and ignore the `server` proc-macro.
vim.lsp.config('rust_analyzer', {
  settings = {
    ['rust-analyzer'] = {
      rustfmt = {
        overrideCommand = { 'leptosfmt', '--stdin', '--rustfmt' },
      },
      procMacro = {
        ignored = {
          leptos_macro = {
            -- "component",
            'server',
          },
        },
      },
    },
  },
})

-- Mason: manages LSP server binaries. Servers it installs are enabled and
-- attached automatically (mason-lspconfig `automatic_enable`), so no per-server
-- boilerplate is needed. Add languages here for a fresh machine, or just run
-- `:MasonInstall <server>` later -- either way they attach with no extra code.
require('mason-lspconfig').setup({
  ensure_installed = { 'lua_ls', 'gopls' },
})
