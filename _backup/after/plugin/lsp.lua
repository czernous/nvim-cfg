local lsp = require("lsp-zero")

lsp.preset("recommended")

lsp.ensure_installed({
    'html',
    'yamlls',
    'cssls',
    'cssmodules_ls',
    'tsserver',
    'eslint',
    'lua_ls',
    'rust_analyzer',
    'csharp_ls',
    'dockerls',
    'elmls',
    'emmet_ls',
    'gopls',
    'golangci_lint_ls',
    'jsonls',
    'bashls',
})

local cmp = require("cmp")
local cmp_select = { behavior = cmp.SelectBehavior.Select }
local cmp_mappings = lsp.defaults.cmp_mappings({
        ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
        ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
        ['<C-y>'] = cmp.mapping.confirm({ select = true }),
        ['<C-Space>'] = cmp.mapping.complete(),
})

lsp.on_attach(function(client, bufnr)
    local opts = { buffer = bufnr, remap = false }
    vim.diagnostic.config({ virtual_text = true })
    vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts, { desc = "[g]o to [d]efinition" })
    vim.keymap.set("n", "K", function() vim.lsp.buf.hover() end, opts, { desc = "hover" })
    vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts,
    { desc = "[v]iew [w]orkspace [s]ymbol" })
    vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts, { desc = "[v]iew [d]iagnostic" })
    vim.keymap.set("n", "[d", function() vim.diagnostic.goto_prev() end, opts, { desc = "go to prv diagnostic" })
    vim.keymap.set("n", "]d", function() vim.diagnostic.goto_next() end, opts, { desc = "go to next diagnostic" })
    vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts,
    { desc = "[v]iew [c]ode [a]ctions" })
    vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts, { desc = "references" })
    vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts, { desc = 'rename' })
    vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
end)

lsp.setup()

