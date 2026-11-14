-- [[ Configure LSP ]]

-- Global LSP keymaps: run once for every server that attaches to a buffer,
-- so Go, Rust, Lua, etc. all get the same mappings (not just one server).
-- See `:help LspAttach`.
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local telescope = require('telescope.builtin')
    local map = function(keys, func, desc, mode)
      vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
    end

    map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
    map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

    map('gd', telescope.lsp_definitions, '[G]oto [D]efinition')
    map('gr', telescope.lsp_references, '[G]oto [R]eferences')
    map('gI', telescope.lsp_implementations, '[G]oto [I]mplementation')
    map('<leader>D', telescope.lsp_type_definitions, 'Type [D]efinition')
    map('<leader>ds', telescope.lsp_document_symbols, '[D]ocument [S]ymbols')
    map('<leader>ws', telescope.lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

    -- Hover docs in a floating window. max_width/max_height cap its size so it
    -- doesn't fill the whole editor. Press K a SECOND time to jump INTO the
    -- float (then scroll with j/k or <C-d>/<C-u>; q or <Esc> closes it).
    map('K', function()
      vim.lsp.buf.hover({ border = 'rounded', max_width = 80, max_height = 20 })
    end, 'Hover Documentation')
    map('<C-k>', function()
      vim.lsp.buf.signature_help({ border = 'rounded', max_width = 80, max_height = 15 })
    end, 'Signature Documentation')
    map('<C-h>', function()
      vim.lsp.buf.signature_help({ border = 'rounded', max_width = 80, max_height = 15 })
    end, 'Signature Help', 'i')

    -- Lesser used LSP functionality
    map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
    map('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
    map('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
    map('<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, '[W]orkspace [L]ist Folders')

    -- Create a command `:Format` local to the LSP buffer
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
require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = { 'lua_ls', 'gopls' },
})
