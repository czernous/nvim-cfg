return {
    require('lspconfig').rust_analyzer.setup {
        -- Other Configs ...
        settings = {
            ["rust-analyzer"] = {
                rustfmt = {
                    overrideCommand = {"leptosfmt", "--stdin", "--rustfmt"}
                },
                procMacro = {
                    ignored = {
                        leptos_macro = {
                            -- optional: --
                            -- "component",
                            "server",
                        },
                    },
                },
            },
        }
    }
}
