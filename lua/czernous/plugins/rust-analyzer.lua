local on_attach = function(client)
    require 'completion'.on_attach(client)
end

return {
    -- The name of the server is passed as the first argument
    vim.lsp.config('rust_analyzer', {
        on_attach = on_attach,
        -- Other Configs ...
        settings = {
            ["rust-analyzer"] = {
                rustfmt = {
                    overrideCommand = { "leptosfmt", "--stdin", "--rustfmt" }
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
    })
}
