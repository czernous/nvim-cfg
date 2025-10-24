-- [[ Configure LSP ]]
--  This function gets run when an LSP connects to a particular buffer.
local on_attach = function(_, bufnr)
  local buf_set_keymap = function(keys, func, desc, mode)
    if desc then
      desc = 'LSP: ' .. desc
    end

    if mode == nil or mode == "" then
      mode = 'n' -- Assign 'n' if mode is nil or an empty string
    end


    vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = desc })
  end

  buf_set_keymap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  buf_set_keymap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  buf_set_keymap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
  buf_set_keymap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  buf_set_keymap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  buf_set_keymap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
  buf_set_keymap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  buf_set_keymap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  buf_set_keymap('K', vim.lsp.buf.hover, 'Hover Documentation')
  buf_set_keymap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')
  buf_set_keymap("<C-h>", vim.lsp.buf.signature_help, 'Signature Help', 'i')

  -- Lesser used LSP functionality
  buf_set_keymap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  buf_set_keymap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  buf_set_keymap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  buf_set_keymap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- mason-lspconfig requires that these setup functions are called in this order
-- before setting up the servers.
require('mason').setup()
require('mason-lspconfig').setup()
-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.
--
--  If you want to override the default filetypes that your language server will attach to you can
--  define the property 'filetypes' to the map in question.
local servers = {
  -- clangd = {},
  -- gopls = {},
  -- pyright = {},
  -- rust_analyzer = {},
  -- tsserver = {},
  -- html = { filetypes = { 'html', 'twig', 'hbs'} },

  lua_ls = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
      -- NOTE: toggle below to ignore Lua_LS's noisy `missing-fields` warnings
      -- diagnostics = { disable = { 'missing-fields' } },
    },
  },
}

-- Setup neovim lua configuration
require('neodev').setup()

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- Ensure the servers above are installed
local mason_lspconfig = require 'mason-lspconfig'

mason_lspconfig.setup {
  ensure_installed = vim.tbl_keys(servers),
}

for server_name, _ in pairs(servers) do
  vim.lsp.config(server_name, {
    capabilities = capabilities,
    on_attach = on_attach,
    settings = servers[server_name],
    filetypes = (servers[server_name] or {}).filetypes,
  })
end
