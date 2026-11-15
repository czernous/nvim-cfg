-- Merged on top of nvim-lspconfig's lua_ls defaults.
return {
  settings = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
      -- Uncomment to silence lua_ls's noisy `missing-fields` warnings:
      -- diagnostics = { disable = { 'missing-fields' } },
    },
  },
}
