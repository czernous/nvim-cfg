return {
    {
        "neovim/nvim-lspconfig",
        -- event = "LazyFile",
        dependencies = {
            -- Automatically install LSPs to stdpath for neovim.
            -- Mason moved orgs: williamboman/* -> mason-org/* (same plugin, current home).
            { 'mason-org/mason.nvim', config = true },
            'mason-org/mason-lspconfig.nvim',

            -- Useful status updates for LSP
            -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
            { 'j-hui/fidget.nvim', opts = {} },
        },
      },

    -- lazydev.nvim: Lua LS types/completion for the Neovim API and plugins,
    -- while editing your config. Replaces the archived folke/neodev.nvim.
    {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
            library = {
                -- Load luvit (vim.uv) types when the `vim.uv` word is found.
                { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
            },
        },
    },
}
