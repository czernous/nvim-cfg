-- Merged on top of nvim-lspconfig's gopls defaults.
return {
  settings = {
    gopls = {
      -- More checks (unused code, likely bugs, simplifications), reported as
      -- warnings and hints -- the linting half of "report, don't auto-fix".
      staticcheck = true,
    },
  },
}
