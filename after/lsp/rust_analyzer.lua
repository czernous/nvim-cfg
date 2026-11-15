-- Merged on top of nvim-lspconfig's rust_analyzer defaults.
local ra = {
  -- Leptos: don't expand the `server` proc-macro (slow / noisy).
  procMacro = { ignored = { leptos_macro = { 'server' } } },
}

-- Leptos: format view! macros with leptosfmt, but only where it's installed;
-- otherwise rust-analyzer's normal rustfmt is used.
if vim.fn.executable('leptosfmt') == 1 then
  ra.rustfmt = { overrideCommand = { 'leptosfmt', '--stdin', '--rustfmt' } }
end

-- Report clippy's lints (style, likely bugs) as you save, when clippy is installed.
if vim.fn.executable('cargo-clippy') == 1 then
  ra.check = { command = 'clippy' }
end

return { settings = { ['rust-analyzer'] = ra } }
